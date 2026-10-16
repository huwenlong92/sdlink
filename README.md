# SDLink

单节点代理入站与客户端管理工具，内置 Web 管理端，使用 SQLite 保存配置、累计用量与限制策略。

- 一个入站对应多个独立客户端凭据。
- 支持 VLESS REALITY、Trojan、Hysteria2、VMess 和 Shadowsocks。
- 保存后自动校验和应用；支持独立停用、额度和到期限制。
- 在线状态、真实流量账本、运行日志、连接信息导出。
- 独立本机设置与账户管理，可选 SDSub 配置和累计流量自动上报；配置版本与流量批次分别持久确认。
- 管理端默认仅监听 localhost；业务入站可监听所有网卡。

此 GitHub 仓库只提供公开说明、安装文件与发行资产，不承载后端和前端源码。

## 界面预览

截图来自本地演示环境，服务器名称和地址均为示例，不含真实凭据。

**登录管理端**

![SDLink 登录管理端](https://raw.githubusercontent.com/huwenlong92/sdlink/main/docs/screenshots/login.png)

## 下载

可用版本与平台以 Releases 中实际列出的完整包和 SHA256 校验文件为准。也可使用已验证的本地完整离线包。

[Releases](https://github.com/huwenlong92/sdlink/releases) · [完整部署说明](deploy/README.md)

在线安装需要 Releases 中存在对应资产，且公开安装文件已同步；若发布列表为空，请先从开发工作区生成离线包。

发行资产命名：

```text
sdlink-<version>-linux-amd64.tar.gz
sdlink-<version>-linux-amd64.tar.gz.sha256
sdlink-<version>-linux-arm64.tar.gz
sdlink-<version>-linux-arm64.tar.gz.sha256
```

包内包含 SDLink 主程序、Web UI、配套运行组件与资源、构建信息、配置样例、systemd 模板和安装脚本。用户只安装和升级 SDLink；内核版本由发行包固定，随 SDLink 一起更新，无需另装内核或配置其路径。解压后应保留完整目录，不要只复制主程序。

## 安装

请先下载和审阅脚本，再执行；不要直接把下载内容通过管道交给 shell。以下使用占位版本 `VERSION_TO_INSTALL`，替换为 Releases 中实际存在的版本。

```sh
curl -fL https://raw.githubusercontent.com/huwenlong92/sdlink/main/scripts/install.sh -o install-sdlink.sh
less install-sdlink.sh
VERSION=VERSION_TO_INSTALL sh install-sdlink.sh
```

完整发行包可直接进行 systemd 新装：

```sh
sudo env VERSION=VERSION_TO_INSTALL INSTALL_SYSTEMD=1 NO_START=1 sh install-sdlink.sh
```

默认不自动启动。修改 `/etc/sdlink/config.yaml` 的 `public_ip` 为实际对外 IP，核对端口后启动：

```sh
sudo systemctl enable --now sdlink
curl -fsS http://localhost:9020/healthz
```

首次账号为 `admin/admin`，随机会话密钥保存在 root-only 的 `/etc/sdlink/sdlink.env`。已有数据库保留原账号密码。

## 访问

```sh
ssh -N -L 19020:localhost:9020 YOUR_SERVER
```

浏览器打开 `http://localhost:19020`。管理后台不需要向公网开放。

## 升级

```sh
sudo env VERSION=VERSION_TO_INSTALL ACTION=upgrade INSTALL_SYSTEMD=1 NO_START=1 sh install-sdlink.sh
```

升级会停服务并备份主程序、配套运行组件、配置、数据库和内核运行状态，保留已有 unit、会话密钥与配置。核对后启动并验证；完整回滚和卸载步骤见[部署说明](deploy/README.md)。

SDLink 保存配置和限制变化时会重启内部内核，已有连接需要重连。公网可达性、域名、证书和防火墙由管理员配置；出口 IP 不必然等于可入站访问的公网入口。

## Docker

本地开发工作区可执行 `make docker-build` 与 `make docker-save`，镜像包含配套内核与全部运行资源。安装目录、Compose、持久化和 admin/admin 初始化见 [Docker 部署](deploy/docker/README.md)。当前 Docker 镜像只用于测试部署，尚未发布 registry 地址。
