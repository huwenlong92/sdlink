# Docker 部署

构建机先生成嵌入 Web 的 Linux SDLink，再把固定版 配套运行组件 一起放入运行镜像。当前使用已远端验证的 SDKit Mirror Debian bookworm-slim 索引，CGO_ENABLED=0；目标主机本轮为 Linux amd64。基础镜像同时支持 amd64/arm64，但业务只按目标架构构建。

```sh
make docker-build
make docker-save
```

`dist/docker/` 仅保存运行制品与导出的镜像，不包含业务源码、配置、数据库或凭据。镜像是本地测试版本，不自动推送 registry 或 GitHub。

## 独立目录与初始配置

服务器使用全新 `/opt/sdlink` 目录。不要把现有其他服务或数据库挂进此容器。先检查没有旧实例或同名目录，复制本目录 compose.yaml、config.yaml.example、image.env.example 和已导出的镜像。

```sh
# root 执行，只用于确认后的全新 SDLink 实例。
install -d -m 0700 /opt/sdlink
install -d -o 10001 -g 10001 -m 0700 /opt/sdlink/data
cd /opt/sdlink
cp config.yaml.example config.yaml
cp image.env.example .env
umask 077
printf 'SDLINK_SESSION_SECRET=%s\nSDLINK_ADMIN_PASSWORD=admin\n' "$(openssl rand -hex 32)" > sdlink.env
```

初始账号 **admin / admin**。会话密钥自动生成；已有 SQLite 沿用原账号，不因重建镜像重置密码。修改配置中的 public_ip 为实际公网 IP；它与监听 0.0.0.0 是不同用途。

`.env` 只放准确 SDLINK_IMAGE 标签；sdlink.env 保存运行环境，权限 0600，不进 Git。config.yaml 无密码，容器 UID 10001 需只读访问（0644）。数据目录只由 UID 10001 写入。compose 文件由 root 维护。

## 网络与启动

采用 Linux host network，入站可动态监听业务端口，不必每次新增端口都修改 Compose。管理端只监听 localhost:9020，内部管理 API 只监听回环 10085；不会向公网发布管理端口。host network 下端口直接属于主机，要核对占用和主机防火墙，不能依赖 Docker bridge 的端口转发规则。

```sh
docker load -i sdlink-0.1.0-linux-amd64.image.tar
docker compose config --quiet
docker compose up -d
docker compose ps
curl -fsS http://localhost:9020/healthz
docker compose logs --tail 100
```

通过 SSH 隧道 `ssh -N -L 19020:localhost:9020 YOUR_SERVER` 后打开 `http://localhost:19020`。HTTPS 管理域名由宿主机现有 Nginx 独立配置，TLS 就绪前使用隧道。业务入口可以先用 IP:port 完成公网测试，再绑定域名。

当前日本部署使用 `jp.link.sdkit.cn` 管理界面，`*.jp.link.sdkit.cn` 绑定各入站，DNS 均解析到 `5.104.85.206`。泛域名只覆盖一层子域；证书需要同时包含根域与泛域名，A 记录本身不会生成证书。

其他部署需要域名时两个足够：一个管理后台域名，一个业务连接域名；业务连接域名仅 DNS 解析到真实公网 IP，不走普通 Cloudflare HTTP 代理，各协议用不同端口。同一个业务域名的证书可用于对应 TLS 协议。REALITY 的连接域名与伪装目标 SNI 分开维护，不需要为每个客户端创建域名。

## 容器权限与持久化

容器以 UID/GID 10001 运行，cap_drop ALL、no-new-privileges、根文件系统只读；/tmp 使用独立 tmpfs，业务状态只写 /var/lib/sdlink。Compose init 转发退出信号，SDLink 关闭内部内核。SQLite、受管快照与 运行日志都在 data；Docker 进程日志限制为 10 MiB × 3，运行文件日志仍需另行归档轮转。

1024 以下业务端口在本模板中不提供额外绑定能力；使用高端口或宿主机前置转发。证书放入本实例的可读目录，并按实际需要追加只读挂载；不挂载整个主机证书库或 Docker socket。

## 更新与回滚

先记录旧镜像 ID/标签。停本实例后备份完整 data、config.yaml、sdlink.env、.env 和 compose.yaml，备份目录 root-only；SQLite WAL/SHM 与 active.json 要一起保存。加载新镜像，修改 .env 中准确标签，再启动和验证。

```sh
docker compose stop
# 此时备份本实例的完整目录，再修改 SDLINK_IMAGE。
docker compose up -d
```

回滚停服务后切回旧镜像；若数据库结构已变化，还要恢复对应的完整备份。不要直接混合两代数据库或只复制正在运行的 .db。`docker compose down` 默认保留绑定目录；不要使用删除数据的命令或删除其他项目容器。

## 验收

确认 healthy、初始登录、实际构建版本、保存后自动启动内部内核；从服务器之外使用真实客户端连接公网入站，检查在线与流量，再停用/启用、检查额度和服务重启恢复。仅 HTTP 健康检查不能代表代理转发验收。

共享 443 的站点目录、迁移和 TCP/UDP 模板见 [Nginx 部署](../nginx/README.md)。
