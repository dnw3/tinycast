#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-run}"
case "$MODE" in
    run|--build-only|--debug|--logs|--telemetry|--verify|--profile) ;;
    *) echo "Usage: $0 [--build-only|--debug|--logs|--telemetry|--verify|--profile]" >&2; exit 2 ;;
esac

APP_NAME="Tinycast Dev"
APP_BUNDLE="$PWD/build/DerivedData/Build/Products/Debug/$APP_NAME.app"
app_pids() {
    ps -axo pid=,comm= | while read -r pid executable; do
        if [ "$executable" = "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ]; then
            echo "$pid"
        fi
    done
}
if [ "$MODE" = "--build-only" ] && [ -n "$(app_pids)" ]; then
    echo "Quit this checkout's Dev app before building into its signed bundle." >&2
    exit 1
fi
while read -r pid; do
    kill "$pid" 2>/dev/null || true
done < <(app_pids)
for attempt in {1..50}; do
    [ -z "$(app_pids)" ] && break
    sleep 0.1
done
if [ -n "$(app_pids)" ]; then
    echo "The current checkout's Dev app has not exited." >&2
    exit 1
fi
BUILD_ARGUMENTS=(-project Tinycast.xcodeproj -scheme Tinycast -configuration Debug
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/DerivedData)
if [ "$MODE" = "--profile" ]; then
    BUILD_ARGUMENTS+=(SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule)
fi
xcodebuild "${BUILD_ARGUMENTS[@]}" build

case "$MODE" in
    --build-only) exit 0 ;;
esac
if [ "$MODE" = "--debug" ]; then
    exec lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
fi
/usr/bin/open -n "$APP_BUNDLE"
case "$MODE" in
    --logs) exec /usr/bin/log stream --info --style compact --predicate 'process == "Tinycast Dev"' ;;
    --telemetry) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.tinycast.app.dev"' ;;
    --verify) sleep 1; app_pids ;;
esac
