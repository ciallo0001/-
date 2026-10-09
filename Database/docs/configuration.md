# 数据库运维

本项目仅管理 PostgreSQL。前端、Go 服务及 Agent 运行配置已移除。

数据库配置在 .env，模板为 .env.example。env:init 生成独立数据库密码与加密密钥，重复执行保留已有值。运行账号 app_backend 和 app_agent 仍保留，它们是数据库权限角色，不是本目录中的服务进程。

## 日常命令

```powershell
npm.cmd run config:check
npm.cmd run db:start
npm.cmd run doctor
npm.cmd run db:backup
npm.cmd run db:stop
```

Windows 数据目录为 .local/pgdata，程序在 .local/pgsql，日志为 .local/postgres.log。中文路径会使用 SUBST 盘符别名，数据库运行时请保留该别名。Docker 使用 compose.yaml 中的持久卷，停止时不要添加 -v。

## 备份与恢复

```powershell
npm.cmd run db:backup
npm.cmd run db:verify-backup -- --file .local/backups/你的备份.dump
npm.cmd run db:restore -- --file .local/backups/你的备份.dump --database app_restore
```

验证创建并清理临时数据库。恢复只允许创建新数据库，不覆盖当前库；恢复后登录会话失效。备份不包含加密密钥，请另行妥善保存 .env。不要把 .env、.local、凭据或备份上传到 GitHub。

## 权限边界

postgres 仅用于数据库运维；应用分别使用 app_backend / app_agent。RLS 依赖可信服务验证身份后设置事务变量。不要将超级用户连接或原始 SQL 暴露给浏览器或模型。远程数据库连接要求校验证书的 TLS。
