# 校园平台 PostgreSQL 数据库

本目录只维护数据库结构、迁移、权限、初始化、备份恢复和数据库测试。数据库中的用户、登录会话、Agent context/memory、校园业务等表是数据模型，保留这些表不代表包含后端服务或 Agent 程序。

## 目录

- db/migrations：001–009 正式迁移（已应用文件不可修改）。
- db/design/campus-platform.full.sql：从全部正式迁移生成的空库 DDL。
- scripts：数据库配置、初始化、加密数据处理、种子、备份恢复和诊断工具。
- tests：配置、种子密码哈希和 PostgreSQL 结构/权限测试。
- docs：数据库设计和运维说明。
- compose.yaml：PostgreSQL Docker 环境。
- .local：本机 PostgreSQL 程序、真实数据、备份和初始化凭据，不提交 Git。

## Windows 本地启动

需要 Node.js 22.18+。在当前目录依次运行：

```powershell
npm.cmd ci
npm.cmd run env:init
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-postgres.ps1
npm.cmd run db:start
npm.cmd run db:init
npm.cmd run check
```

默认连接为 127.0.0.1:5432/app_dev。仅需启动已有库时运行 npm.cmd run db:start。
种子账号可按需运行 npm.cmd run db:seed 或 npm.cmd run db:seed:student；后者仅供开发演示，不作为真人核验。

## Docker

安装 Docker 后，运行 npm.cmd ci、npm.cmd run env:init、docker compose up -d --wait，再执行 npm.cmd run db:init。不要同时启动相同端口的便携实例和 Docker。

## 管理

- npm.cmd run db:status / db:stop：查看状态 / 停止数据库。
- npm.cmd run doctor：检查连接、迁移校验和、密钥与数据库账号权限。
- npm.cmd run db:backup：生成备份。
- npm.cmd run design:build：重新生成空库 DDL。
- npm.cmd test：数据库相关测试（使用开发集群）。

.env 包含密码和加密密钥，不能上传。已有数据目录、备份及密钥保留，不要删除或重新生成。详见 [运维说明](docs/configuration.md)。

完整 DDL 仅用于空库；已有库一律使用 db:init 增量迁移。数据库结构不等于已完成业务 API、支付、通知或真人核验。
