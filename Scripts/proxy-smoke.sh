#!/bin/bash
# Drive the shipped ProxyManager against the pinned core on loopback fixtures.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

./Scripts/fetch-mihomo.sh > /dev/null || exit 1
source Vendor/mihomo/core.env
CORE="$PWD/build/vendor/mihomo/mihomo"
case "$(uname -m)" in
    arm64) ARCHIVE="$PWD/build/vendor/mihomo/mihomo-darwin-arm64-$MIHOMO_VERSION.gz" ;;
    *) ARCHIVE="$PWD/build/vendor/mihomo/mihomo-darwin-amd64-compatible-$MIHOMO_VERSION.gz" ;;
esac
for port in 47001 47002 47053 47100 47200 47790; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN > /dev/null 2>&1; then
        echo "✗ port $port is in use; the smoke test needs 47001-47790 free" >&2
        exit 1
    fi
done

WORK="$(mktemp -d /tmp/tc-proxy-smoke.XXXXXX)"
PIDS=()
cleanup() {
    for pid in "${PIDS[@]}"; do kill "$pid" 2> /dev/null; done
    wait 2> /dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/www/geo/geosite" "$WORK/www/geo/geoip" "$WORK/lists" "$WORK/server" "$WORK/bundle/Contents/Helpers"

# Two subscriptions (YAML, base64 share links), a node file, and the smart routes' rule lists.
python3 -I - "$WORK" << 'PY'
import base64, os, sys, urllib.parse
work = sys.argv[1]
secret = "tinycast-smoke"
def link(port, name):
    user = base64.urlsafe_b64encode(f"aes-128-gcm:{secret}".encode()).decode().rstrip("=")
    return f"ss://{user}@127.0.0.1:{port}#" + urllib.parse.quote(name)
def node(name, port):
    return f'  - {{name: "{name}", type: ss, server: 127.0.0.1, port: {port}, cipher: aes-128-gcm, password: "{secret}"}}'
open(f"{work}/www/sub-a.yaml", "w").write("\n".join([
    "proxies:", node("🇭🇰 香港 01", 47001), node("🇯🇵 日本 01", 47002), node("剩余流量：100 GB", 47001),
    node("🇺🇸 美国 01", 47009), "proxy-groups:", '  - {name: 自带, type: select, proxies: ["🇭🇰 香港 01"]}',
    "rules:", "  - MATCH,自带"]) + "\n")
links = "\n".join([link(47001, "香港 02"), link(47002, "SG 01")]) + "\n"
open(f"{work}/www/sub-b.txt", "w").write(base64.b64encode(links.encode()).decode())
open(f"{work}/nodes.txt", "w").write(link(47002, "🇸🇬 新加坡 自建") + "\n")
lists = {
    "geosite/category-ads-all": ["ads.test"], "geosite/private": ["lan.test"],
    "geosite/category-ai-!cn": ["ai.test"], "geosite/netflix": ["netflix.com"],
    "geosite/youtube": ["youtube.com"], "geosite/disney": ["disneyplus.com"], "geosite/spotify": ["spotify.com"],
    "geosite/tiktok": ["tiktok.com"], "geosite/telegram": ["telegram.org"], "geosite/github": ["github.com"],
    "geosite/apple": ["apple.com"], "geosite/geolocation-!cn": ["example.org"], "geosite/cn": ["baidu.com"],
    "geoip/private": ["10.0.0.0/8", "192.168.0.0/16"], "geoip/netflix": ["23.246.0.0/18"],
    "geoip/telegram": ["91.108.4.0/22"], "geoip/cn": ["1.2.4.0/24"],
}
for path, items in lists.items():
    open(f"{work}/lists/{path.replace('/', '__')}.txt", "w").write("\n".join(items) + "\n")
PY
for list in "$WORK"/lists/*.txt; do
    name="$(basename "$list" .txt)"
    case "$name" in geosite__*) behavior=domain ;; *) behavior=ipcidr ;; esac
    "$CORE" convert-ruleset "$behavior" text "$list" "$WORK/www/geo/${name/__//}.mrs" || exit 1
done

# A second core plays both nodes and the DNS server, resolving every test name to loopback.
cat > "$WORK/server/config.yaml" << 'YAML'
log-level: warning
ipv6: false
listeners:
  - {name: hk, type: shadowsocks, port: 47001, listen: 127.0.0.1, cipher: aes-128-gcm, password: tinycast-smoke}
  - {name: jp, type: shadowsocks, port: 47002, listen: 127.0.0.1, cipher: aes-128-gcm, password: tinycast-smoke}
hosts: {ai.test: 127.0.0.1, baidu.com: 127.0.0.1, github.com: 127.0.0.1, example.org: 127.0.0.1}
dns: {enable: true, listen: "127.0.0.1:47053", ipv6: false, use-hosts: true, nameserver: ["127.0.0.1:47999"]}
rules: ["MATCH,DIRECT"]
YAML
"$CORE" -d "$WORK/server" -f "$WORK/server/config.yaml" > "$WORK/server.log" 2>&1 &
PIDS+=($!)

# Files on 47200, with a usage header on subscription A; a keep-alive target on 47100.
cat > "$WORK/serve.py" << 'PY'
import http.server, sys, threading
root = sys.argv[1]
class Files(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=root, **kwargs)
    def end_headers(self):
        if self.path.startswith("/sub-a"):
            self.send_header("subscription-userinfo", "upload=1024; download=2048; total=1073741824; expire=0")
        super().end_headers()
    def log_message(self, *args):
        pass
class Target(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def reply(self, body):
        self.send_response(204 if self.path == "/generate_204" else 200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        return body
    def do_GET(self):
        self.wfile.write(self.reply(b"" if self.path == "/generate_204" else
                                    f"ok {self.headers.get('Host')} {self.path}\n".encode()))
    def do_HEAD(self):
        self.reply(b"")
    def log_message(self, *args):
        pass
class Server(http.server.ThreadingHTTPServer):
    request_queue_size = 128
target = Server(("127.0.0.1", 47100), Target)
threading.Thread(target=target.serve_forever, daemon=True).start()
Server(("127.0.0.1", 47200), Files).serve_forever()
PY
python3 -I "$WORK/serve.py" "$WORK/www" &
PIDS+=($!)

# The bundle starts with no core in Contents/Helpers, so the driver first downloads one in-app.
swiftc -swift-version 6 Tinycast/Features/Proxy/Model/*.swift Tinycast/Features/Proxy/Service/*.swift \
    Tinycast/Features/Updates/Model/AppVersion.swift Tinycast/Features/Updates/Model/ReleaseArchitecture.swift \
    Tinycast/Platform/AppPaths.swift Tinycast/Platform/KeychainSecretStore.swift Tinycast/Platform/ProcessExit.swift \
    Tinycast/Platform/Compression/Zlib.swift Tinycast/Features/Updates/Service/ToolRunner.swift \
    Tests/proxy-smoke.swift -o "$WORK/bundle/proxy-smoke" || exit 1
for port in 47001 47053 47100 47200; do
    for _ in $(seq 50); do lsof -nP -iTCP:"$port" -sTCP:LISTEN > /dev/null 2>&1 && break; sleep 0.1; done
done

SMOKE_WORK="$WORK" SMOKE_BASE=http://127.0.0.1:47200 SMOKE_TARGET=127.0.0.1:47100 SMOKE_DNS=127.0.0.1:47053 \
    SMOKE_MIXED=47790 SMOKE_NODES="$WORK/nodes.txt" SMOKE_VERSION="$MIHOMO_VERSION" SMOKE_ARCHIVE="$ARCHIVE" \
    SMOKE_CORE="$CORE" "$WORK/bundle/proxy-smoke"
status=$?
if [ "$status" -ne 0 ] && [ -f "$WORK/Proxy/Core/core.log" ]; then
    echo "--- core.log"
    tail -20 "$WORK/Proxy/Core/core.log"
fi
exit "$status"
