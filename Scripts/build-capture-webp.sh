#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

WEBP_BUILD="${1:?Usage: build-capture-webp.sh output-directory}"
mkdir -p "$WEBP_BUILD"
WEBP_BUILD="$(cd "$WEBP_BUILD" && pwd)"
WEBP_SDK="$(xcrun --sdk macosx --show-sdk-path)"
WEBP_OBJECTS=()
for source in Vendor/libwebp/src/{dec,dsp,enc,utils,mux}/*.c Vendor/libwebp/sharpyuv/*.c; do
    case "$source" in */anim_encode.c) continue ;; esac
    object="$WEBP_BUILD/$(basename "$(dirname "$source")")-$(basename "$source" .c).o"
    xcrun clang -c -O2 -std=c99 -isysroot "$WEBP_SDK" -mmacosx-version-min=26.0 \
        -DWEBP_USE_THREAD=1 -I Vendor/libwebp "$source" -o "$object"
    WEBP_OBJECTS+=("$object")
done
xcrun libtool -static -o "$WEBP_BUILD/libCaptureWebP.a" "${WEBP_OBJECTS[@]}"
