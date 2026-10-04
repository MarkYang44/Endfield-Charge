#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
flags=(--disable-sandbox --build-system native --cache-path "$PWD/.build/swift-cache")
developer_path=$(xcode-select -p)
if [[ "$developer_path" == */CommandLineTools ]]; then
  frameworks="$developer_path/Library/Developer/Frameworks"
  flags+=(-Xswiftc -F -Xswiftc "$frameworks" -Xlinker -rpath -Xlinker "$frameworks")
fi
swift test "${flags[@]}"
