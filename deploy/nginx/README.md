# 服务 Nginx 目录与 443 入口

沿用 larkit.us 的目录结构；日本于 2026-10-14 按同一结构迁移。配置由管理员部署，不由域名绑定表单修改。

| 目录或文件 | 用途 |
| --- | --- |
| /etc/nginx/nginx.conf | 主配置：http 和 stream 分开，分别 include |
| /etc/nginx/modules-enabled | 发行版动态模块，包含 stream 模块 |
| /etc/nginx/conf.d/*.conf | http 共用配置，如可信代理及 upstream |
| /etc/nginx/sites-available/<域名>.conf | 各 HTTPS 站点配置 |
| /etc/nginx/sites-enabled/<域名>.conf | 指向 sites-available 的启用软链接 |
| /etc/nginx/stream.d/tls-sni-routing.conf | TCP 443 的 TLS SNI 分流 |
| /etc/nginx/stream.d/<HY2 域名>.conf | UDP 443 透传到对应 HY2 入站 |
| /etc/nginx/ssl.d/<域名>/ | HTTP 站点的证书与私钥 |

`http` 内保留 `conf.d/*.conf` 和 `sites-enabled/*.conf`。在主配置顶层追加与 http 平级的：

```nginx
stream {
    include /etc/nginx/stream.d/*.conf;
}
```

TCP 443 由 stream 监听。REALITY 按实际伪装 SNI（示例 www.cloudflare.com）转到 SDLink 入站；其他 SNI 转到内部 HTTPS 后端 127.0.0.1:8443。HTTP 站点保留 80，HTTPS 从公网 443 改为 `listen 127.0.0.1:8443 ssl;`，证书、域名和原反向代理保持。UDP 443 与 TCP 独立，转到一个 HY2 入站；QUIC TLS 由 SDLink 内核处理。

两个 example 文件的 10000、10002 是示例后端端口，必须改为实际入站端口；不要复制到 http 的 conf.d。连接域名的 A 记录不会创建转发。转发完成后，才将 SDLink 域名绑定端口设为 443。

## 新机器

先检查 `nginx -V`、发行版模块包、443/8443 占用和域名解析，再安装匹配的 stream 模块。日本 Debian 13 已核验 nginx 与 libnginx-mod-stream 均为 1.26.3-3+deb13u9，安装仅新增模块，没有升级 Nginx；见 [Debian 包说明](https://packages.debian.org/trixie/libnginx-mod-stream)。其他系统须按其当前 ABI 与官方源核对。

准备站点、证书与可回滚配置，确认内部服务已监听后，`nginx -t` 成功才 reload。分别验证 HTTP、HTTPS、REALITY 和 HY2；TCP 443 可访问不代表 UDP 443 可访问。

## 已有机器迁移

先审计实际 include 和所有 HTTPS 监听，备份主配置、站点、stream 及 sdacme 配置。对既有 HTTPS 站点执行明确的内部端口迁移；不能只新增 stream TCP 443，与现有 HTTP SSL 监听冲突。

sdacme 的 `nginx.https_listen` 同步为 `["127.0.0.1:8443 ssl"]`，避免未来新增站点重新占公网 443。当前 sdacmectl 不接受 `[::1]:8443`，不要把 Nginx 支持的格式直接当成工具配置支持。原 HTTP-01 路径、续期时间和证书位置保留。迁移后必须核对 cron 的实际可执行文件版本：日本旧 sdacme 0.1.0 无法解析 reporting，新 sdacmectl 0.2.0 可以；实际运行新版 cron 成功后，已将旧任务路径切换为新版，保留原调度和日志。

逐站点记录迁移前后状态，执行 nginx -t、reload、sdacmectl config check / doctor；任一步失败立即恢复本次改动。日本六个 HTTPS 站点的迁移前后状态一致。

## 回滚与边界

只恢复本次备份的配置，撤回新增 stream TCP 入口与对应内部监听改动，检查成功后 reload。不要删除其他站点、证书或数据库。实际备份路径与验证结果应记录在本机部署验收文档中。

当前透传没有配置 PROXY protocol；源 IP 可能被后端观察为回环，影响日志与 内核的非回环在线统计。不要据此推断客户端未转发，也不要把累计流量变化当作实时在线。真实客户端 IP 透传仍需独立设计与验证。

官方参考：[SNI 预读](https://nginx.org/en/docs/stream/ngx_stream_ssl_preread_module.html)、[TCP/UDP 代理](https://nginx.org/en/docs/stream/ngx_stream_proxy_module.html)。
