param([ValidateSet('start', 'stop', 'status')][string]$Action = 'start')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
# PostgreSQL's Windows bootstrap can mix the system code page with UTF-8 when
# absolute paths contain Chinese characters. A per-user SUBST drive gives the
# same project directory an ASCII path; data is never moved outside the project.
if ($projectRoot -match '[^\x00-\x7F]') {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class ProjectDriveAlias {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint QueryDosDevice(string name, StringBuilder target, int size);
}
'@
    $mappedRoot = $null
    $freeLetters = @()
    foreach ($letter in @('P','Q','R','S','T','U','V','W','X','Y','Z')) {
        $target = [Text.StringBuilder]::new(4096)
        $found = [ProjectDriveAlias]::QueryDosDevice(($letter + ':'), $target, $target.Capacity)
        if ($found -gt 0 -and $target.ToString() -eq ('\??\' + $projectRoot)) {
            $mappedRoot = $letter + ':\'
            break
        }
        if ($found -eq 0 -and !(Test-Path -LiteralPath ($letter + ':\'))) { $freeLetters += $letter }
    }
    if (!$mappedRoot) {
        foreach ($letter in $freeLetters) {
            & subst.exe ($letter + ':') $projectRoot
            if ($LASTEXITCODE -ne 0) { throw 'Unable to create a project-local ASCII drive alias.' }
            $mappedRoot = $letter + ':\'
            break
        }
    }
    if (!$mappedRoot) { throw 'No free drive letter is available for the PostgreSQL path alias.' }
    $projectRoot = $mappedRoot
    Set-Location -LiteralPath $projectRoot
}
$bin = Join-Path $projectRoot '.local\pgsql\bin'
$data = Join-Path $projectRoot '.local\pgdata'
$log = Join-Path $projectRoot '.local\postgres.log'
$pgCtl = Join-Path $bin 'pg_ctl.exe'
if (!(Test-Path -LiteralPath $pgCtl)) { throw 'Run scripts/install-postgres.ps1 first, or use Docker Compose.' }
if (!(Test-Path -LiteralPath '.env')) { throw 'Run npm run env:init first.' }
$config = @{}
foreach ($line in Get-Content -LiteralPath '.env') {
    if ($line -match '^([A-Z_]+)=(.*)$') { $config[$Matches[1]] = $Matches[2] }
}
if ($Action -eq 'status') {
    & $pgCtl status -D $data
    exit $LASTEXITCODE
}
if ($Action -eq 'stop') {
    & $pgCtl stop -D $data -m fast -w
    exit $LASTEXITCODE
}
if ($config['PGHOST'] -ne '127.0.0.1') { throw 'Portable PostgreSQL is for localhost development only.' }
$port = 0
if (![int]::TryParse($config['PGPORT'], [ref]$port) -or $port -lt 1024 -or $port -gt 65535) { throw 'Invalid PGPORT.' }
if (!(Test-Path -LiteralPath (Join-Path $data 'PG_VERSION'))) {
    $pwfile = Join-Path $projectRoot '.local\initdb-password.tmp'
    try {
        [IO.File]::WriteAllText($pwfile, $config['POSTGRES_PASSWORD'], [Text.UTF8Encoding]::new($false))
        & (Join-Path $bin 'initdb.exe') -D $data -U $config['POSTGRES_USER'] --encoding=UTF8 --locale=C --auth=scram-sha-256 "--pwfile=$pwfile"
        if ($LASTEXITCODE -ne 0) { throw 'initdb failed.' }
    } finally {
        if (Test-Path -LiteralPath $pwfile) { Remove-Item -LiteralPath $pwfile }
    }
    $settings = @"

# Project-local development instance
listen_addresses = '127.0.0.1'
port = $port
password_encryption = 'scram-sha-256'
timezone = 'UTC'
log_timezone = 'UTC'
"@
    [IO.File]::AppendAllText((Join-Path $data 'postgresql.conf'), $settings, [Text.UTF8Encoding]::new($false))
}
& $pgCtl status -D $data *> $null
if ($LASTEXITCODE -eq 0) { Write-Output 'PostgreSQL is already running.'; exit 0 }
$arguments = @('start', '-D', ('"' + $data + '"'), '-l', ('"' + $log + '"'), '-w', '-t', '30')
$process = Start-Process -FilePath $pgCtl -ArgumentList $arguments -WindowStyle Hidden -PassThru
# Start-Process -Wait waits for the server's entire process tree as well.
# Wait only for pg_ctl, which exits once the detached server is ready.
$process.WaitForExit()
$process.Refresh()
if ($process.ExitCode -ne 0) { throw "PostgreSQL failed to start; inspect $log" }
Write-Output "PostgreSQL is running on 127.0.0.1:$port."

