#!/bin/bash
# メニューバーアプリ (dist/Video2MD.app) と配布用 dmg (dist/Video2MD.dmg) を作る。
set -euo pipefail
cd "$(dirname "$0")"

APP=dist/Video2MD.app
rm -rf dist && mkdir -p "$APP/Contents/MacOS"

swiftc -O -o "$APP/Contents/MacOS/Video2MD" Sources/Core.swift Sources/app/main.swift
cp scripts/Info.plist "$APP/Contents/Info.plist"

# ad-hoc 署名（Developer ID が無くても動く。配布時の警告を消すには正式な署名と公証が必要）
codesign --force --sign - "$APP"

mkdir -p dist/dmg
cp -R "$APP" dist/dmg/
ln -s /Applications dist/dmg/Applications
hdiutil create -volname "Video2MD" -srcfolder dist/dmg -ov -format UDZO dist/Video2MD.dmg >/dev/null
rm -rf dist/dmg

echo "できました:"
echo "  $APP"
echo "  dist/Video2MD.dmg"
