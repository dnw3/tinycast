#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
derived=${1:-build/DerivedData}
objects="$derived/Build/Intermediates.noindex/Tinycast.build/Debug/Tinycast.build/Objects-normal"
[ -d "$objects" ] || { echo "Build Debug with SWIFT_EMIT_LOC_STRINGS=YES first." >&2; exit 1; }
files=()
while IFS= read -r file; do files+=("$file"); done < <(find "$objects" -name '*.stringsdata' -type f)
[ ${#files[@]} -gt 0 ] || { echo "No compiler localization data found." >&2; exit 1; }
xcrun xcstringstool sync Tinycast/Resources/Localizable.xcstrings --stringsdata "${files[@]}"
node Scripts/check-localization.js "$objects"
