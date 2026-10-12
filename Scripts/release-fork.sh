#!/bin/bash
# Build, sign and (with --publish) release a fork build for friends: release-fork.sh <X.Y.Z> [--publish].
# Only this Mac's identity will do: the updater installs a release whose leaf matches the running copy.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=dnw3/tinycast
IDENTITY="Tinycast Self-Signed"
VERSION=${1:?Usage: release-fork.sh <X.Y.Z> [--publish]}
PUBLISH=${2:-}
TAG="v$VERSION"
DERIVED=build/ForkRelease
APP="$DERIVED/Build/Products/Release/Tinycast.app"
ZIP="build/dist/Tinycast-$VERSION.zip"
NOTES="build/dist/Tinycast-$VERSION-notes.md"

fail() { echo "✗ $*" >&2; exit 1; }

# The updater reads only X.Y.Z and X.Y.Z-beta.N; friends run the stable channel.
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version must be X.Y.Z, got '$VERSION'."
[ -z "$PUBLISH" ] || [ "$PUBLISH" = --publish ] || fail "Unknown option '$PUBLISH'."

git fetch -q origin main upstream-main
[ "$(git branch --show-current)" = main ] || fail "Release from main."
[ -z "$(git status --porcelain)" ] || fail "Commit or stash local changes first."
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main must match origin/main."
grep -q "static let repository = \"$REPO\"" Tinycast/Features/Updates/Model/ReleaseFeed.swift ||
    fail "ReleaseFeed.repository must be $REPO, or friends would update to upstream builds."

leaf=$(security find-identity -v -p codesigning | awk -v id="\"$IDENTITY\"" '$0 ~ id {print tolower($2); exit}')
[ -n "$leaf" ] || fail "\"$IDENTITY\" is not in the keychain; import it per docs/signing.md."

previous=$(gh release list -R "$REPO" --exclude-drafts --exclude-pre-releases --limit 1 \
    --json tagName --jq '.[0].tagName // empty')
if [ -n "$previous" ]; then
    newest=$(printf '%s\n%s\n' "${previous#v}" "$VERSION" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n1)
    [ "$newest" = "$VERSION" ] && [ "$previous" != "$TAG" ] ||
        fail "$VERSION must be newer than the last release $previous."
fi

echo "→ Building $TAG"
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
    -derivedDataPath "$DERIVED" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)" \
    build > "$DERIVED.log" 2>&1 || { grep -E 'error:' "$DERIVED.log" | sort -u | head -20; fail "Build failed; see $DERIVED.log."; }

echo "→ Verifying"
built=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
[ "$built" = "$VERSION" ] || fail "Built version is $built, not $VERSION."
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")" = com.tinycast.app ] ||
    fail "Friends' copies update only on the com.tinycast.app channel."
while IFS= read -r binary; do
    file -b "$binary" | grep -q Mach-O || continue
    [ "$(lipo -archs "$binary")" = arm64 ] || fail "${binary#"$APP"/} is not arm64-only."
done < <(find "$APP/Contents" -type f -perm -u+x)
codesign --verify --deep --strict "$APP"
codesign -d -r- "$APP" 2>&1 | grep -q "certificate leaf = H\"$leaf\"" ||
    fail "The app is not signed by \"$IDENTITY\" ($leaf)."

echo "→ Packaging"
mkdir -p build/dist
rm -f "$ZIP"
# The only zip that keeps the code signature verifiable; plain `zip` breaks the seal.
ditto -c -k --keepParent --sequesterRsrc "$APP" "$ZIP"

upstream=$(git log -1 --format='%h（%cs）' "$(git merge-base HEAD origin/upstream-main)")
{
    echo "基于上游 Tinycast main $upstream，包含 Capture（截图、贴图、录屏、OCR）与 Translation（划词与截图翻译）。"
    echo
    if [ -n "$previous" ]; then
        echo "### 自 $previous 以来"
        echo
        git log --first-parent --format='- %s' "$previous..HEAD" | head -n 30
    fi
    echo
    echo "<!-- tinycast:install -->"
    echo
    echo "### 首次安装"
    echo
    echo "1. 先退出并删除其他来源的 Tinycast（包括 Homebrew 安装的 \`tinycast\`），两者不能并存。"
    echo "2. 下载 \`Tinycast-$VERSION.zip\`，解压后把 Tinycast 拖进「应用程序」。"
    echo "3. 第一次打开会被系统拦下：到「系统设置 → 隐私与安全性」底部点「仍要打开」。"
    echo "   也可以在终端运行 \`xattr -dr com.apple.quarantine /Applications/Tinycast.app\` 后再打开。"
    echo "4. 按引导授予辅助功能等权限。"
    echo
    echo "之后在设置中开启自动检查更新即可，应用会从本仓库更新，已授的权限保留。"
    echo "不要再用 Homebrew 安装或升级 \`tinycast\`，它装的是不含这些功能的上游版本。"
    echo
    echo "此版本未经 Apple 公证，仅供熟人使用。源码（AGPL-3.0）：https://github.com/$REPO/tree/$(git rev-parse --short HEAD)"
} > "$NOTES"

echo "✓ $ZIP ($(du -h "$ZIP" | cut -f1)) and $NOTES"
if [ "$PUBLISH" != --publish ]; then
    echo "Review them, then re-run with --publish."
    exit 0
fi

echo "→ Publishing $TAG"
gh release create "$TAG" "$ZIP" -R "$REPO" --target "$(git rev-parse HEAD)" \
    --title "Tinycast $VERSION" --notes-file "$NOTES"
git fetch -q origin "refs/tags/$TAG:refs/tags/$TAG"
echo "✓ https://github.com/$REPO/releases/tag/$TAG"
