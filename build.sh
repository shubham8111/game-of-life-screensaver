#!/bin/zsh
# ./build.sh            build build/GameOfLife.saver (universal)
# ./build.sh --install  ...and install it to ~/Library/Screen Savers
# ./build.sh explore    build the offline explorer, build/explore
set -euo pipefail
cd "$(dirname "$0")"

# Everything except the screen saver view; shared with the explorer.
ENGINE=(Sources/Life.swift Sources/Patterns.swift Sources/Stage.swift Sources/Scenes.swift)

if [[ "${1:-}" == "explore" ]]; then
  mkdir -p build
  swiftc -O -module-name Explore "${ENGINE[@]}" Tools/explore/main.swift -o build/explore
  echo "Built build/explore"
  exit 0
fi

OUT=build/GameOfLife.saver
rm -rf "$OUT" build/obj && mkdir -p "$OUT/Contents/MacOS" build/obj

for arch in arm64 x86_64; do
  swiftc -O -whole-module-optimization -module-name GameOfLife \
    -target $arch-apple-macos14.0 -emit-library \
    -o build/obj/GameOfLife-$arch "${ENGINE[@]}" Sources/GameOfLifeView.swift \
    -framework ScreenSaver -framework AppKit
done
lipo -create build/obj/GameOfLife-* -output "$OUT/Contents/MacOS/GameOfLife"
cp Info.plist "$OUT/Contents/Info.plist"
codesign --force --sign - "$OUT"
echo "Built $OUT"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Library/Screen\ Savers
  rm -rf ~/Library/Screen\ Savers/GameOfLife.saver
  cp -R "$OUT" ~/Library/Screen\ Savers/
  killall legacyScreenSaver 2>/dev/null || true
  echo "Installed to ~/Library/Screen Savers/GameOfLife.saver"
fi
