# SDLink 二进制部署与运维

本文说明完整 SDLink 发行包的二进制与 systemd 安装。核验日期：2026-10-14。当前代码仍在开发工作区，GitHub 发布仓库已存在但为空，尚无 Release；本文的在线下载仅在首次发布后适用。日本 Docker 测试实例已升级到自带配套内核的版本，配置、证书、账本和真实转发已验收。

## 范围与方式

系统集成脚本面向具有 systemd、useradd、getent、curl、tar、SHA256 工具及 OpenSSL 的 Linux；构建目标为 amd64 / arm64。发行版实际兼容性仍需目标主机验收，不宣称已覆盖所有 Linux。源码构建在开发机完成，服务器无需 Go、Node 或 pnpm。systemd 操作需要 root；服务进程使用独立的 sdlink 用户。二进制完整安装包与 Docker 均包含配套运行组件，升级时一同替换，不单独管理内核版本。

当前没有发行版仓库包或官方 APT/RPM 仓库。Docker 运行镜像构建与独立 Compose 模板已新增，见[Docker 部署](../deploy/docker/README.md)。便捷安装脚本来自公开发布仓库，应先下载审阅；不要直接 curl | sh。Docker 服务启动及公网验收按部署记录独立确认，不能把构建成功等同于已验证的线上运行。

源码保留在原 Gitee 仓库：后端 `sd0/sdlink`，前端 `sd0/sdlink-web`。GitHub `huwenlong92/sdlink` 只发布资产和公开安装文件，源码 origin 不改。对照 Go 的 [GOOS/GOARCH](https://go.dev/doc/install/source#environment) 交叉编译，不需要照搬 sdhook 的 Rust Docker 构建。

## Makefile 与本地打包

开发依赖：当前 go.mod 要求 Go 1.25.10；前端 package.json 固定 pnpm 11.1.2。还需 Python 3、curl、Git、tar、sha256sum 或 shasum，前端 Node 版本应符合锁定 Vite 的要求。当前 go.mod 固定已发布的 sdkit v0.1.28，已移除本地 replace，不需要额外共享框架 checkout；包内 build-info.txt 记录实际编译依赖。正式发布前仍需审阅确切源码提交并验证发行资产，依赖固定不等于资产已发布。

```sh
make help
make install-web
make test
make test-install
make build
./bin/sdlink -version
make release-dry-run
LINUX_ARCH=arm64 make release-linux-dry-run
make sync-github-public-dry-run
```

`VERSION` 文件为版本来源，也可 `VERSION=0.1.0 make release-dry-run`。产物位于 `dist/release/v<version>/`，Web UI 只构建一次后嵌入各平台二进制。每个包有独立 `.sha256`，不会在另一个架构打包时覆盖前一个架构的校验文件。开发工作区构建显示 dirty，不自动改版本、暂存或提交。

正式发布是独立的人工操作：审阅、测试、提交源码，登录 gh 后执行 `make release`。该命令同步公开文件并发布当前平台及 Linux 资产。`make publish-readme` 只同步 README、安装脚本、部署说明、配置与 unit 白名单，不推送业务源码。单独发布可用 `make release-current` / `make release-linux`；已有同名资产拒绝覆盖。公开脚本的源码入口与安装下载地址不同，参见[发布首页](https://github.com/huwenlong92/sdlink/releases)。

## 安装前检查

目标服务器执行只读检查；有现有安装时跳到升级或迁移章节，不覆盖新装：

```sh
cat /etc/os-release
uname -m
uname -r
systemctl --version
id
ss -lntup
systemctl status sdlink --no-pager
ls -ld /etc/sdlink /var/lib/sdlink /opt/sdlink
getent passwd sdlink
getent group sdlink
df -h /var/lib /opt
```

不存在的服务或目录报错是正常检查结果。核对管理端 9020、内部回环管理端口 10085、拟用业务端口；若其他服务占用 10085，先确认端口归属；SDLink 不接管现有服务。不要删除原服务、配置、证书或数据库。

## 配套运行组件

完整 SDLink 包同时包含主程序、runtime 内核与资源文件。安装脚本自动校验、部署；运行时优先使用包内配套组件，升级 SDLink 会同时升级内核，不需要用户另行安装、下载或管理内核版本。

解压后直接运行时，runtime 与 sdlink 位于同一目录；安装脚本将运行组件放到 `<PREFIX>/libexec/sdlink/runtime`。主程序、配套运行组件和第三方许可证须一同保留。新装无需设置内核路径或日志路径；默认在数据目录下管理状态与日志。

## 全新安装

可以先从本机传输打包预演产物，无需等待 GitHub Release。以下在 **服务器** 执行，替换为实际架构及版本的完整包路径：

```sh
sha256sum -c sdlink-0.1.0-linux-amd64.tar.gz.sha256
tar -xzf sdlink-0.1.0-linux-amd64.tar.gz
sudo env LOCAL_ARCHIVE="$PWD/sdlink-0.1.0-linux-amd64.tar.gz" \
  INSTALL_SYSTEMD=1 NO_START=1 \
  sh sdlink-0.1.0-linux-amd64/scripts/install.sh
```

同目录必须有 `sdlink-0.1.0-linux-amd64.tar.gz.sha256`；脚本校验压缩包后才安装。存在安装目录、unit、二进制或同名用户时拒绝新装，必须先确认归属。脚本创建 root 写入、sdlink 组可读的服务配置和 root-only 随机密钥，服务用户只能写 `/var/lib/sdlink`；默认不启动。

配置与路径：

| 文件 | 用途 |
| --- | --- |
| /usr/local/bin/sdlink | 服务二进制 |
| /etc/sdlink/config.yaml | 服务配置，root:sdlink 0640 |
| /etc/sdlink/sdlink.env | 初始密码 admin、随机会话密钥，root-only |
| /var/lib/sdlink/sdlink.db | SQLite，含 WAL/SHM |
| /var/lib/sdlink/kernel | 默认成功快照、运行配置与日志；升级保留原状态目录 |
| /usr/local/libexec/sdlink/runtime | 配套内核与资源，随 SDLink 安装升级 |

将 public_ip 明确设为可入站访问的节点 IP。当前自动逻辑只读取网卡，不查询出口公网 IP；NAT、云端映射或多 IP 场景必须核对实际入口。业务默认监听 0.0.0.0；0.0.0.0 不是客户端连接地址。域名可稍后在入站中配置。管理端维持 localhost:9020。

```sh
sudo systemctl enable --now sdlink
sudo systemctl status sdlink --no-pager
curl -fsS http://localhost:9020/healthz
sudo journalctl -u sdlink -n 100 --no-pager
```

用 SSH 隧道访问管理端：`ssh -N -L 19020:localhost:9020 YOUR_SERVER`，浏览器打开 `http://localhost:19020`。larkit.jp 实测时替换 YOUR_SERVER，先核对主机和端口，不自动更改该主机已有服务。

## 真正的验证闭环

核对 `sdlink -version`、包 SHA256、build-info.txt 和 `/healthz` 的构建版本；dirty 表示来自未提交工作区。新装无客户端时不应开放匿名业务监听。登录创建入站与客户端，等待自动生效；设置公网入口后从另一台机器使用导出配置连接，核对上传/下载账本、在线状态，停用后不能连接，重新启用仍受额度与期限限制。验证限制触发、重启恢复及日志；仅健康接口或版本成功不算公网转发验收。

## 升级、迁移与回滚

systemd 安装升级使用 `ACTION=upgrade INSTALL_SYSTEMD=1 NO_START=1`，并提供 VERSION 或 LOCAL_ARCHIVE。脚本停服务，在 `/var/backups/sdlink/<UTC时间>-<PID>/` 保存旧二进制、整个配置目录、完整数据目录（包括 WAL/SHM、日志及 active.json）和 unit，再更换主程序和配套运行组件；保留管理员配置、env 和 unit。失败时服务保持停止，核对备份后同时恢复主程序与对应 runtime，再恢复配置和数据；不自动清库。

自定义旧目录属于迁移：停旧实例，做一致备份，确认新目录与 service 用户权限，再迁移整个数据库及受管目录；不要只拷贝运行中的 `.db`，也不要两个实例共用状态目录。旧配置不能直接套新装流程。

回滚先停服务，保存升级后的状态作为第二份备份。若新版本改变过 SQLite 结构，必须一起恢复升级前完整 data 和 config；只降级二进制不能保证兼容。下面的路径必须替换为核对过的备份目录，恢复只覆盖明确的 SDLink 路径：

```sh
sudo systemctl stop sdlink
# 先备份当前 /etc/sdlink 与 /var/lib/sdlink；确认 /var/lib/sdlink 仅包含本实例数据。
sudo install -m 0755 /var/backups/sdlink/BACKUP_ID/sdlink /usr/local/bin/sdlink
sudo install -m 0644 /var/backups/sdlink/BACKUP_ID/sdlink.service /etc/systemd/system/sdlink.service
# 按备份清单同时恢复配套 runtime、config 与 data，包含 WAL/SHM，避免混用两代文件。
# 原 runtime 应先移到新的故障留存目录，再将备份中的 runtime 恢复到 /usr/local/libexec/sdlink/runtime。
sudo systemctl daemon-reload
sudo systemctl start sdlink
curl -fsS http://localhost:9020/healthz
```

为避免误覆盖，数据库目录恢复留给管理员依据准确备份清单执行；未恢复数据时不能宣称完整回滚。

## 日常维护与卸载

查看 `systemctl status sdlink` 和 `journalctl -u sdlink`。页面管理入站与客户端；内部内核的启动、校验与恢复由 SDLink 负责，不需要另启内核服务。unit 不支持 reload，使用 `systemctl restart sdlink`，已有连接会中断。

日志位于受管目录，发行安装器尚未自动安装文件轮转规则。安装后应按实际路径和服务权限，为明确的 error/access 文件配置宿主机轮转与保留策略。copytruncate 不需重启内核，但存在小量日志丢失窗口，轮转规则不应匹配业务快照或数据库。Docker stdout 限额不能替代内核文件轮转。

卸载仅在确认不再使用时执行：停止并禁用 SDLink，备份配置和数据，再移除 `/etc/systemd/system/sdlink.service`、`/usr/local/bin/sdlink` 并 daemon-reload。默认保留 `/etc/sdlink`、`/var/lib/sdlink`、`/usr/local/libexec/sdlink`、系统用户和备份。永久删除这些内容是单独的破坏性操作，不放入普通卸载脚本。

## 防火墙与故障判断

只放行实际业务端口（TCP 或 HY2 的 UDP）；不开放 9020 和内部回环管理端口。核对云安全组、主机防火墙及 SELinux/AppArmor，不关闭这些保护来排错。模板使用低权限用户，默认使用 1024 以上的业务端口；443 需另行配置准确的绑定能力或前置转发。

- `address already in use`：检查管理或业务端口占用，改变本实例配置，不停止未知进程。
- 公网地址仍是 127.0.0.1 / 内网：修正 public_ip 或配置入站公网入口；不要用监听地址替代。
- TLS 文件不可读：确保 sdlink 用户能读取证书，受 ProtectHome 限制的文件移到服务可读的专用目录。
- 进程运行但配置未生效：查看管理端的错误信息、journal 和 运行错误日志；原成功配置可能已回滚。
- 下载 404：当前尚无发布资产，使用本地离线包；不要把空 Releases 当已发布。

systemd 模板字段按官方 [service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) / [exec](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html) 文档核对。已有模板和数据需独立维护；源码编译的二进制不受发行版包管理器自动更新。
