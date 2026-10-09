$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$local = Join-Path $projectRoot '.local'
$archive = Join-Path $local 'postgresql-windows-x64.zip'
if (Test-Path -LiteralPath (Join-Path $local 'pgsql\bin\postgres.exe')) {
    Write-Output 'Project-local PostgreSQL already exists.'
    exit 0
}
New-Item -ItemType Directory -Force -Path $local | Out-Null
# EDB is the Windows binary distributor linked by postgresql.org/download/windows/.
if (!(Test-Path -LiteralPath $archive)) {
    & curl.exe -fL --retry 2 --connect-timeout 20 --max-time 600 -o "$archive.part" 'https://get.enterprisedb.com/postgresql/postgresql-18.6-4-windows-x64-binaries.zip'
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL download failed.' }
    Move-Item -LiteralPath "$archive.part" -Destination $archive
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
    foreach ($entry in $zip.Entries) {
        if ($entry.FullName -notmatch '^pgsql/(bin|lib|share)/' -or !$entry.Name) { continue }
        $destination = [IO.Path]::GetFullPath((Join-Path $local $entry.FullName))
        if (!$destination.StartsWith($local + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid archive path.' }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $true)
    }
} finally { $zip.Dispose() }
& (Join-Path $local 'pgsql\bin\postgres.exe') --version
if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL runtime verification failed.' }

