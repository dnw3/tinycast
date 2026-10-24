#!/bin/bash
# Unpack the core pinned in Vendor/mihomo/core.env into build/vendor/mihomo/, keeping its archive.
set -euo pipefail
cd "$(dirname "$0")/.."
source Vendor/mihomo/core.env

ARCH="${1:-$(uname -m)}"
case "$ARCH" in
    arm64) ASSET="mihomo-darwin-arm64-$MIHOMO_VERSION.gz" SHA256="$MIHOMO_SHA256_ARM64" ;;
    x86_64) ASSET="mihomo-darwin-amd64-compatible-$MIHOMO_VERSION.gz" SHA256="$MIHOMO_SHA256_X86_64" ;;
    *)
        echo "usage: fetch-mihomo.sh [arm64|x86_64]" >&2
        exit 2
        ;;
esac

DEST=build/vendor/mihomo
if [ -x "$DEST/mihomo" ] && [ "$(cat "$DEST/VERSION" 2> /dev/null)" = "$MIHOMO_VERSION $ARCH" ]; then
    echo "✓ mihomo $MIHOMO_VERSION ($ARCH) is already in $DEST"
    exit 0
fi

matches() { echo "$SHA256  $1" | shasum -a 256 -c - > /dev/null 2>&1; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$DEST"
# The archive stays beside the binary: an upgrade leaves it here, and the smoke test serves it.
if ! [ -f "$DEST/$ASSET" ] || ! matches "$DEST/$ASSET"; then
    curl -fsSL --retry 3 -o "$WORK/$ASSET" \
        "https://github.com/MetaCubeX/mihomo/releases/download/$MIHOMO_VERSION/$ASSET"
    matches "$WORK/$ASSET" || {
        echo "✗ $ASSET does not match the SHA-256 pinned in Vendor/mihomo/core.env" >&2
        exit 1
    }
    mv "$WORK/$ASSET" "$DEST/$ASSET"
fi
gunzip -c "$DEST/$ASSET" > "$WORK/mihomo"
chmod 755 "$WORK/mihomo"
mv "$WORK/mihomo" "$DEST/mihomo"
echo "$MIHOMO_VERSION $ARCH" > "$DEST/VERSION"
echo "✓ mihomo $MIHOMO_VERSION ($ARCH) → $DEST/mihomo"
