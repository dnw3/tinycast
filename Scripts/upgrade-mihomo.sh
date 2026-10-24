#!/bin/bash
# Move the pinned core to the newest mihomo release, or the one named; `--check` changes nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
source Vendor/mihomo/core.env

CHECK=0
TAG=""
for argument in "$@"; do
    case "$argument" in
        --check) CHECK=1 ;;
        v[0-9]*) TAG="$argument" ;;
        *)
            echo "usage: upgrade-mihomo.sh [--check] [vX.Y.Z]" >&2
            exit 2
            ;;
    esac
done

WORK="$(mktemp -d)"
FINISHED=0
# Once the pin is rewritten, any way out short of the end puts the old one back.
cleanup() {
    if [ "$FINISHED" = 0 ] && [ -f "$WORK/backup/core.env" ]; then
        cp "$WORK/backup/core.env" "$WORK/backup/mihomo-LICENSE" Vendor/mihomo/
        cp "$WORK/backup/NOTICE.md" NOTICE.md
        ./Scripts/fetch-mihomo.sh > /dev/null 2>&1 || true
        echo "  The pin stays at $MIHOMO_VERSION." >&2
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT
mkdir "$WORK/download" "$WORK/core" "$WORK/backup"

API=https://api.github.com/repos/MetaCubeX/mihomo/releases
if [ -n "$TAG" ]; then URL="$API/tags/$TAG"; else URL="$API/latest"; fi
HEADERS=(-H "Accept: application/vnd.github+json")
# Anonymous requests share 60 an hour per address, which a proxy exit can exhaust.
if command -v gh > /dev/null && TOKEN="$(gh auth token 2> /dev/null)"; then
    HEADERS+=(-H "Authorization: Bearer $TOKEN")
fi
curl -fsSL --retry 3 "${HEADERS[@]}" -o "$WORK/download/release.json" "$URL" || {
    echo "✗ GitHub did not answer for ${TAG:-the latest release}" >&2
    exit 1
}

python3 -I - "$WORK/download/release.json" > "$WORK/release.txt" << 'PY'
import json, re, sys
release = json.load(open(sys.argv[1]))
tag = release.get("tag_name") or ""
if not re.fullmatch(r"v\d+\.\d+\.\d+", tag) or release.get("draft") or release.get("prerelease"):
    sys.exit(f"✗ {tag or 'the release'} is not a stable release")
digests = {asset.get("name"): asset.get("digest") or "" for asset in release.get("assets", [])}
print(tag)
for name in (f"mihomo-darwin-arm64-{tag}.gz", f"mihomo-darwin-amd64-compatible-{tag}.gz"):
    digest = digests.get(name, "")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        sys.exit(f"✗ {tag} publishes no SHA-256 for {name}")
    print(digest.removeprefix("sha256:"))
published = release.get("published_at") or ""
print(published if re.fullmatch(r"[0-9TZ:-]+", published) else "")
PY
{
    read -r TAG
    read -r SHA_ARM64
    read -r SHA_X86_64
    read -r PUBLISHED
} < "$WORK/release.txt"

if [ "$CHECK" = 1 ]; then
    echo "pinned  $MIHOMO_VERSION"
    echo "latest  $TAG  (published $PUBLISHED)"
    [ "$TAG" = "$MIHOMO_VERSION" ] || echo "Run Scripts/upgrade-mihomo.sh $TAG to move to it."
    exit 0
fi
if [ "$TAG" = "$MIHOMO_VERSION" ]; then
    echo "✓ mihomo $TAG is already pinned"
    exit 0
fi

ARM_ASSET="mihomo-darwin-arm64-$TAG.gz"
INTEL_ASSET="mihomo-darwin-amd64-compatible-$TAG.gz"
for pair in "$ARM_ASSET:$SHA_ARM64" "$INTEL_ASSET:$SHA_X86_64"; do
    asset="${pair%%:*}" sha256="${pair##*:}"
    curl -fsSL --retry 3 -o "$WORK/download/$asset" \
        "https://github.com/MetaCubeX/mihomo/releases/download/$TAG/$asset"
    echo "$sha256  $WORK/download/$asset" | shasum -a 256 -c - > /dev/null || {
        echo "✗ $asset does not match the SHA-256 GitHub publishes for it" >&2
        exit 1
    }
done

case "$(uname -m)" in
    arm64) HOST_ASSET="$ARM_ASSET" GOARCH=arm64 ;;
    *) HOST_ASSET="$INTEL_ASSET" GOARCH=amd64 ;;
esac
gunzip -c "$WORK/download/$HOST_ASSET" > "$WORK/core/mihomo"
chmod 755 "$WORK/core/mihomo"
IDENTITY="$("$WORK/core/mihomo" -v)"
IDENTITY="${IDENTITY%%$'\n'*}"
case "$IDENTITY" in
    "Mihomo Meta $TAG darwin $GOARCH "*) ;;
    *)
        echo "✗ the $TAG binary describes itself as: $IDENTITY" >&2
        exit 1
        ;;
esac

curl -fsSL --retry 3 -o "$WORK/download/LICENSE" "https://raw.githubusercontent.com/MetaCubeX/mihomo/$TAG/LICENSE"
cp Vendor/mihomo/core.env Vendor/mihomo/mihomo-LICENSE NOTICE.md "$WORK/backup/"
LICENSE_CHANGED=0
if ! cmp -s "$WORK/download/LICENSE" Vendor/mihomo/mihomo-LICENSE; then
    cp "$WORK/download/LICENSE" Vendor/mihomo/mihomo-LICENSE
    LICENSE_CHANGED=1
fi
cat > Vendor/mihomo/core.env << ENV
# The pinned mihomo release. Scripts/upgrade-mihomo.sh rewrites it; nothing else should.
MIHOMO_VERSION=$TAG
MIHOMO_SHA256_ARM64=$SHA_ARM64
MIHOMO_SHA256_X86_64=$SHA_X86_64
ENV
OLD="${MIHOMO_VERSION//./\\.}"
sed -i '' -e "s|^## mihomo $OLD\$|## mihomo $TAG|" -e "s|mihomo/tree/$OLD|mihomo/tree/$TAG|" NOTICE.md
if ! grep -q "^## mihomo $TAG\$" NOTICE.md || ! grep -q "mihomo/tree/$TAG" NOTICE.md; then
    echo "✗ NOTICE.md no longer names the mihomo version where this script expects it" >&2
    exit 1
fi

mkdir -p build/vendor/mihomo
mv "$WORK/download/$HOST_ASSET" build/vendor/mihomo/
./Scripts/fetch-mihomo.sh
if ! ./Scripts/proxy-smoke.sh; then
    echo "✗ $TAG failed the smoke test" >&2
    exit 1
fi
FINISHED=1

echo
echo "✓ mihomo $MIHOMO_VERSION → $TAG ($PUBLISHED)"
echo "  Notes: https://github.com/MetaCubeX/mihomo/releases/tag/$TAG"
echo "  Review and commit Vendor/mihomo/core.env and NOTICE.md."
if [ "$LICENSE_CHANGED" = 1 ]; then
    echo "  ! mihomo-LICENSE changed upstream: read the new text before shipping it."
fi
