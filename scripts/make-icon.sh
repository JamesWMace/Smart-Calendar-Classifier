#!/bin/zsh
# Regenerates the app icon set from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
set_dir=SmartCalendarClassifier/Assets.xcassets/AppIcon.appiconset
mkdir -p "$set_dir"
master=$(mktemp -d)/icon-1024.png
swift scripts/make-icon.swift "$master"

images=()
for points in 16 32 128 256 512; do
  for scale in 1 2; do
    pixels=$((points * scale))
    name="icon_${points}x${points}@${scale}x.png"
    sips -z $pixels $pixels "$master" --out "$set_dir/$name" >/dev/null
    images+=("{ \"idiom\": \"mac\", \"size\": \"${points}x${points}\", \"scale\": \"${scale}x\", \"filename\": \"$name\" }")
  done
done
printf '{\n  "images": [\n    %s\n  ],\n  "info": { "version": 1, "author": "xcode" }\n}\n' "${(pj:,\n    :)images}" > "$set_dir/Contents.json"
printf '{\n  "info": { "version": 1, "author": "xcode" }\n}\n' > SmartCalendarClassifier/Assets.xcassets/Contents.json
echo "Wrote $set_dir"
