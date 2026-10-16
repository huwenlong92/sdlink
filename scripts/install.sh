#!/bin/sh
# Download and verify first. Existing systemd installs require ACTION=upgrade.
set -eu
repo=${GITHUB_REPO:-huwenlong92/sdlink}
version=${VERSION:-}
prefix=${PREFIX:-/usr/local}
action=${ACTION:-install}
case "$action" in install|upgrade) ;; *) echo 'ACTION must be install or upgrade' >&2; exit 1 ;; esac
case "$prefix" in /*) ;; *) echo 'PREFIX must be absolute' >&2; exit 1 ;; esac
case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; *) echo 'Unsupported operating system' >&2; exit 1 ;; esac
case "$(uname -m)" in x86_64|amd64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) echo 'Unsupported CPU architecture' >&2; exit 1 ;; esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
if [ -n "${LOCAL_ARCHIVE:-}" ]; then
 archive=$LOCAL_ARCHIVE
 checksum=${LOCAL_CHECKSUM:-$LOCAL_ARCHIVE.sha256}
 [ -f "$archive" ] && [ -f "$checksum" ] || { echo 'Missing local archive/checksum' >&2; exit 1; }
 cp "$archive" "$work/$(basename "$archive")"
 cp "$checksum" "$work/checksum.txt"
else
 command -v curl >/dev/null
 if [ -z "$version" ]; then
  version=$(curl --fail --silent --show-error --location --connect-timeout 10 --max-time 30 "https://api.github.com/repos/$repo/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)
 fi
 printf '%s\n' "$version" | LC_ALL=C grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+([.-][a-zA-Z0-9.-]+)?$' || { echo 'No valid published release was found; specify VERSION or LOCAL_ARCHIVE' >&2; exit 1; }
 version=${version#v}
 asset=sdlink-$version-$os-$arch.tar.gz
 base=https://github.com/$repo/releases/download/v$version
 curl --fail --silent --show-error --location --connect-timeout 10 --max-time 300 "$base/$asset" -o "$work/$asset"
 curl --fail --silent --show-error --location --connect-timeout 10 --max-time 30 "$base/$asset.sha256" -o "$work/checksum.txt"
 archive=$work/$asset
fi
asset=$(basename "$archive")
# Only a single plain archive filename is allowed in the downloaded checksum.
line=$(cat "$work/checksum.txt")
expected=$(printf '%s\n' "$line" | awk '{print $1}')
listed=$(printf '%s\n' "$line" | awk '{print $2}')
[ "$listed" = "$asset" ] || { echo 'Checksum filename does not match archive' >&2; exit 1; }
printf '%s\n' "$expected" | LC_ALL=C grep -Eq '^[0-9a-fA-F]{64}$' || { echo 'Invalid SHA256 checksum' >&2; exit 1; }
if command -v sha256sum >/dev/null; then actual=$(sha256sum "$work/$asset" | awk '{print $1}'); else actual=$(shasum -a 256 "$work/$asset" | awk '{print $1}'); fi
[ "$actual" = "$expected" ] || { echo 'Archive checksum verification failed' >&2; exit 1; }
# Reject traversal, links and unexpected top-level names before extraction.
tar -tzf "$work/$asset" > "$work/members"
root=${asset%.tar.gz}
case "$root" in sdlink-*-$os-$arch) ;; *) echo 'Archive platform does not match this host' >&2; exit 1 ;; esac
awk -v root="$root" 'index($0,root "/") != 1 || $0 ~ /(^|\/)\.\.(\/|$)/ {bad=1} END {exit bad}' "$work/members" || { echo 'Unsafe archive members' >&2; exit 1; }
tar -tvzf "$work/$asset" | awk 'substr($0,1,1)!="-" && substr($0,1,1)!="d" {bad=1} END {exit bad}' || { echo 'Archive links/special files are not accepted' >&2; exit 1; }
tar -xzf "$work/$asset" -C "$work"
package=$work/$root
[ -f "$package/sdlink" ] && [ -x "$package/sdlink" ] || { echo 'Missing SDLink binary' >&2; exit 1; }
[ -x "$package/runtime/kernel" ] || { echo 'Incomplete SDLink package: bundled runtime missing' >&2; exit 1; }
for name in VERSION geoip.dat geosite.dat LICENSE NOTICE UPSTREAM-README.md; do
 [ -s "$package/runtime/$name" ] || { echo "Incomplete SDLink package: runtime/$name missing" >&2; exit 1; }
done
kernel_version=$(cat "$package/runtime/VERSION")
printf '%s\n' "$kernel_version" | LC_ALL=C grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo 'Invalid bundled runtime version' >&2; exit 1; }
actual_kernel=$("$package/runtime/kernel" version | head -n 1 | awk '{print $2}')
[ "$actual_kernel" = "$kernel_version" ] || { echo 'Bundled runtime version mismatch' >&2; exit 1; }
"$package/sdlink" -version
activate_package() {
 runtime_parent=$prefix/libexec/sdlink
 runtime_target=$runtime_parent/runtime
 [ ! -L "$runtime_target" ] && { [ ! -e "$runtime_target" ] || [ -d "$runtime_target" ]; } || { echo 'Unsafe runtime installation path' >&2; exit 1; }
 install -d -m 0755 "$prefix/bin" "$prefix/libexec" "$runtime_parent"
 runtime_stage=$(mktemp -d "$runtime_parent/.runtime-new-XXXXXX")
 chmod 0755 "$runtime_stage"
 install -m 0755 "$package/runtime/kernel" "$runtime_stage/kernel"
 for name in VERSION geoip.dat geosite.dat LICENSE NOTICE UPSTREAM-README.md; do
  install -m 0644 "$package/runtime/$name" "$runtime_stage/$name"
 done
 binary_stage=$prefix/bin/.sdlink-new-$$
 install -m 0755 "$package/sdlink" "$binary_stage"
 runtime_previous=
 if [ -d "$runtime_target" ]; then
  runtime_previous=$runtime_parent/runtime.previous-$(date -u '+%Y%m%dT%H%M%SZ')-$$
  mv "$runtime_target" "$runtime_previous"
 fi
 if ! mv "$runtime_stage" "$runtime_target"; then
  [ -z "$runtime_previous" ] || mv "$runtime_previous" "$runtime_target"
  exit 1
 fi
 if ! mv "$binary_stage" "$prefix/bin/sdlink"; then
  mv "$runtime_target" "$runtime_stage"
  [ -z "$runtime_previous" ] || mv "$runtime_previous" "$runtime_target"
  exit 1
 fi
 [ -z "$runtime_previous" ] || echo "Previous runtime: $runtime_previous"
}
if [ "$action" = install ] && { [ -e "$prefix/bin/sdlink" ] || [ -e "$prefix/libexec/sdlink/runtime" ]; }; then
 echo 'Existing SDLink installation found; inspect it and use ACTION=upgrade' >&2
 exit 1
fi
if [ "${INSTALL_SYSTEMD:-0}" = 1 ]; then
 [ "$os" = linux ] && [ "$(id -u)" = 0 ] || { echo 'systemd install requires Linux and root' >&2; exit 1; }
 [ "$prefix" = /usr/local ] || { echo 'systemd template requires PREFIX=/usr/local' >&2; exit 1; }
 command -v systemctl >/dev/null
 if [ "$action" = install ]; then
  [ ! -e /etc/sdlink ] && [ ! -e /var/lib/sdlink ] && [ ! -e /etc/systemd/system/sdlink.service ] && [ ! -e "$prefix/bin/sdlink" ] || { echo 'Existing installation found; back up and use ACTION=upgrade' >&2; exit 1; }
  ! getent passwd sdlink >/dev/null && ! getent group sdlink >/dev/null || { echo 'Existing sdlink user found; inspect its ownership before installation' >&2; exit 1; }
  command -v openssl >/dev/null
  useradd --system --user-group --home-dir /var/lib/sdlink --shell /usr/sbin/nologin sdlink
  install -d -o root -g sdlink -m 0750 /etc/sdlink
  install -d -o sdlink -g sdlink -m 0700 /var/lib/sdlink
  install -o root -g sdlink -m 0640 "$package/deploy/config.yaml.example" /etc/sdlink/config.yaml
  umask 077
  printf 'SDLINK_SESSION_SECRET=%s\nSDLINK_ADMIN_PASSWORD=%s\n' "$(openssl rand -hex 32)" "admin" > /etc/sdlink/sdlink.env
 else
  [ -f /etc/sdlink/config.yaml ] && [ -f /etc/sdlink/sdlink.env ] && [ -f /etc/systemd/system/sdlink.service ] || { echo 'Incomplete systemd installation; follow manual migration instructions' >&2; exit 1; }
  backup=/var/backups/sdlink/$(date -u '+%Y%m%dT%H%M%SZ')-$$
  install -d -m 0700 "$backup"
  systemctl stop sdlink
  cp -a /etc/sdlink "$backup/config"
  cp -a /var/lib/sdlink "$backup/data"
  cp -a /etc/systemd/system/sdlink.service "$backup/sdlink.service"
  cp -a "$prefix/bin/sdlink" "$backup/sdlink"
  if [ -d "$prefix/libexec/sdlink/runtime" ]; then cp -a "$prefix/libexec/sdlink/runtime" "$backup/runtime"; fi
  echo "Stopped service; backup: $backup"
 fi
 activate_package
 # Configuration and data remain intact; the bundled runtime upgrades with SDLink.
 if [ "$action" = install ]; then install -m 0644 "$package/deploy/sdlink.service" /etc/systemd/system/sdlink.service; fi
 systemctl daemon-reload
 if [ "${NO_START:-1}" = 0 ]; then systemctl enable --now sdlink; else echo 'Installed without starting; configure public_ip and run systemctl enable --now sdlink'; fi
 echo 'Admin credentials are in /etc/sdlink/sdlink.env (root-only); never paste them into logs.'
else
 if [ "$action" = install ] && [ -e "$prefix/bin/sdlink" ]; then echo 'Existing binary found; use ACTION=upgrade' >&2; exit 1; fi
 install -d "$prefix/bin"
 if [ -f "$prefix/bin/sdlink" ]; then cp -p "$prefix/bin/sdlink" "$prefix/bin/sdlink.previous"; fi
 activate_package
 echo "Installed $prefix/bin/sdlink; configuration and service startup are manual."
fi
