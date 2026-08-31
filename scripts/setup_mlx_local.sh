#!/usr/bin/env bash
# Clone local MLX checkouts for StoryPromptKit (siblings of the vovozinha folder).
#
# Uses Prism mlx-swift (no host CudaBuild plugin — remote 0.31.6+ breaks Xcode 27 iOS builds)
# and mlx-swift-lm @ 3.31.4 patched to path-depend on that mlx-swift.
#
# Layout:
#   Projects/mlx-swift
#   Projects/mlx-swift-lm
#   Projects/vovozinha
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PARENT="$(cd "$ROOT/.." && pwd)"
MLX_SWIFT="$PARENT/mlx-swift"
MLX_LM="$PARENT/mlx-swift-lm"
MLX_LM_REF="${MLX_LM_REF:-3.31.4}"

echo "==> mlx-swift (Prism @ prism, no CudaBuild) → $MLX_SWIFT"
if [[ -d "$MLX_SWIFT/.git" ]]; then
  git -C "$MLX_SWIFT" fetch origin 2>/dev/null || true
  if git -C "$MLX_SWIFT" rev-parse --verify origin/prism >/dev/null 2>&1; then
    git -C "$MLX_SWIFT" checkout prism 2>/dev/null || true
    git -C "$MLX_SWIFT" pull --ff-only origin prism 2>/dev/null || true
  fi
else
  git clone -b prism https://github.com/PrismML-Eng/mlx-swift.git "$MLX_SWIFT" \
    || git clone https://github.com/ml-explore/mlx-swift.git "$MLX_SWIFT"
fi
git -C "$MLX_SWIFT" submodule update --init --recursive

echo "==> mlx-swift-lm @ $MLX_LM_REF → $MLX_LM"
if [[ -d "$MLX_LM/.git" ]]; then
  git -C "$MLX_LM" fetch origin --tags 2>/dev/null || true
  git -C "$MLX_LM" checkout -f "$MLX_LM_REF"
else
  git clone https://github.com/ml-explore/mlx-swift-lm.git "$MLX_LM"
  git -C "$MLX_LM" checkout -f "$MLX_LM_REF"
fi

PKG="$MLX_LM/Package.swift"
python3 - <<'PY' "$PKG"
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
pat = r'\.package\(\s*url:\s*"https://github\.com/ml-explore/mlx-swift(?:\.git)?"\s*,\s*[^)]+\)'
new, n = re.subn(pat, '.package(path: "../mlx-swift")', text, count=1)
if n == 0:
    pat2 = r'\.package\(\s*url:\s*"https://github\.com/ml-explore/mlx-swift(?:\.git)?"\s*\)'
    new, n = re.subn(pat2, '.package(path: "../mlx-swift")', text, count=1)
new = new.replace('.package(path: "../mlx-swift"))', '.package(path: "../mlx-swift")')
path.write_text(new)
print("patched mlx-swift-lm Package.swift (n=%d)" % n)
PY

echo ""
echo "Done."
echo "  $MLX_SWIFT"
echo "  $MLX_LM"
echo "MetalToolchain: xcodebuild -downloadComponent MetalToolchain"
