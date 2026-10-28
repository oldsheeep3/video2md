#!/bin/bash
# クローンしたらこれを実行するだけ。初回は Swift でビルドし、以降はビルド済みを使う。
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift が見つかりません。次を実行して Command Line Tools を入れてから、もう一度 ./start.sh を実行してください:"
  echo "  xcode-select --install"
  exit 1
fi

BIN=build/video2md
if [ ! -x "$BIN" ] || [ Sources/Core.swift -nt "$BIN" ] || [ Sources/cli/main.swift -nt "$BIN" ]; then
  echo "ビルド中…"
  mkdir -p build
  if ! swiftc -O -o "$BIN" Sources/Core.swift Sources/cli/main.swift 2>build/build.log; then
    cat build/build.log
    exit 1
  fi
fi

exec "$BIN" "$@"
