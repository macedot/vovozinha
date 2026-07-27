#!/usr/bin/env bash
# Fetch CLiteRTLM XCFrameworks into the local LiteRT-LM checkout used by StoryPromptKit.
set -euo pipefail
VOVO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Package.swift: .package(path: "../../../LiteRT-LM") from Packages/StoryPromptKit
# -> vovozinha/../LiteRT-LM when Packages is under vovozinha... wait:
# Packages/StoryPromptKit -> ../../../LiteRT-LM = sibling of Projects if path is
# /Users/thiago/Projects/vovozinha/Packages/StoryPromptKit -> ../../../ = /Users/thiago/
# Actually: StoryPromptKit + ../ = Packages, + ../../ = vovozinha, + ../../../ = Projects
# so LiteRT-LM is /Users/thiago/Projects/LiteRT-LM
LITERT="${LITERT_LM_PATH:-$VOVO_ROOT/../LiteRT-LM}"
LITERT="$(cd "$LITERT" && pwd)"
if [[ ! -f "$LITERT/Package.swift" ]]; then
  echo "LiteRT-LM not found at $LITERT"
  echo "Clone: git clone -b v0.13.1 https://github.com/google-ai-edge/LiteRT-LM.git $LITERT"
  exit 1
fi
OUT="$LITERT/.xcframeworks"
mkdir -p "$OUT"
VER=v0.13.0
for name in CLiteRTLM CLiteRTLM_mac; do
  if [[ -d "$OUT/${name}.xcframework" ]]; then
    echo "OK $OUT/${name}.xcframework"
    continue
  fi
  zip="/tmp/${name}.xcframework.zip"
  echo "Downloading $name ($VER)..."
  curl -L --fail -o "$zip" \
    "https://github.com/google-ai-edge/LiteRT-LM/releases/download/${VER}/${name}.xcframework.zip"
  unzip -q -o "$zip" -d "$OUT"
  echo "Installed $OUT/${name}.xcframework"
done
echo "Done. In Xcode: File → Packages → Reset Package Caches, then clean build."
