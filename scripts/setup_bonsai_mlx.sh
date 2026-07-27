#!/usr/bin/env bash
# Clone Prism mlx-swift (1-bit) + mlx-swift-lm next to the vovozinha parent folder and
# point mlx-swift-lm at the local Prism mlx-swift (package identity / 1-bit kernels).
#
# Layout after setup (sibling of vovozinha under Projects/):
#   Projects/mlx-swift
#   Projects/mlx-swift-lm
#   Projects/vovozinha
#
# Usage (from repo root):
#   ./scripts/setup_bonsai_mlx.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PARENT="$(cd "$ROOT/.." && pwd)"
MLX_SWIFT="$PARENT/mlx-swift"
MLX_LM="$PARENT/mlx-swift-lm"

echo "==> Prism mlx-swift (1-bit) → $MLX_SWIFT"
if [[ -d "$MLX_SWIFT/.git" ]]; then
  git -C "$MLX_SWIFT" fetch origin
  git -C "$MLX_SWIFT" checkout prism
  git -C "$MLX_SWIFT" pull --ff-only origin prism || true
else
  git clone -b prism https://github.com/PrismML-Eng/mlx-swift.git "$MLX_SWIFT"
fi
git -C "$MLX_SWIFT" submodule update --init --recursive

# Apply Prism patches when present (until upstreamed).
if [[ -d "$MLX_SWIFT/patches" ]]; then
  if [[ -f "$MLX_SWIFT/patches/mlx-quantized-dispatch-1bit.patch" ]]; then
    git -C "$MLX_SWIFT/Source/Cmlx/mlx" apply --check \
      "$MLX_SWIFT/patches/mlx-quantized-dispatch-1bit.patch" 2>/dev/null \
      && git -C "$MLX_SWIFT/Source/Cmlx/mlx" apply \
        "$MLX_SWIFT/patches/mlx-quantized-dispatch-1bit.patch" || true
  fi
  if [[ -f "$MLX_SWIFT/patches/mlx-c-global-scale-nullopt.patch" ]]; then
    git -C "$MLX_SWIFT/Source/Cmlx/mlx-c" apply --check \
      "$MLX_SWIFT/patches/mlx-c-global-scale-nullopt.patch" 2>/dev/null \
      && git -C "$MLX_SWIFT/Source/Cmlx/mlx-c" apply \
        "$MLX_SWIFT/patches/mlx-c-global-scale-nullopt.patch" || true
  fi
fi

# Pin mlx-swift-lm to a release that still builds against Prism mlx-swift ~0.31.1
# (main requires MLXArray.maskFill from newer upstream mlx-swift).
MLX_LM_REF="${MLX_LM_REF:-3.31.4}"

echo "==> mlx-swift-lm @ $MLX_LM_REF → $MLX_LM"
if [[ -d "$MLX_LM/.git" ]]; then
  git -C "$MLX_LM" fetch origin --tags
  git -C "$MLX_LM" checkout -f "$MLX_LM_REF"
else
  git clone --branch "$MLX_LM_REF" https://github.com/ml-explore/mlx-swift-lm.git "$MLX_LM" \
    || git clone https://github.com/ml-explore/mlx-swift-lm.git "$MLX_LM"
  git -C "$MLX_LM" checkout -f "$MLX_LM_REF"
fi

PKG="$MLX_LM/Package.swift"
if [[ ! -f "$PKG" ]]; then
  echo "error: missing $PKG" >&2
  exit 1
fi

# Point mlx-swift-lm at local Prism mlx-swift (same package identity "mlx-swift").
if grep -q 'path: "../mlx-swift"' "$PKG" 2>/dev/null; then
  echo "==> Package.swift already uses path ../mlx-swift"
else
  echo "==> Patching mlx-swift-lm Package.swift to use path ../mlx-swift"
  python3 - <<'PY' "$PKG"
import re, sys
path = sys.argv[1]
text = open(path).read()
# Replace remote mlx-swift package dependency (url + version constraint).
pat = r'\.package\(\s*url:\s*"https://github\.com/ml-explore/mlx-swift(?:\.git)?"\s*,\s*[^)]+\)'
new, n = re.subn(pat, '.package(path: "../mlx-swift")', text, count=1)
if n == 0:
    pat2 = r'\.package\(\s*url:\s*"https://github\.com/ml-explore/mlx-swift(?:\.git)?"\s*\)'
    new, n = re.subn(pat2, '.package(path: "../mlx-swift")', text, count=1)
if n == 0 and '.package(path: "../mlx-swift")' not in text:
    new = text.replace(
        "dependencies: [",
        'dependencies: [\n        .package(path: "../mlx-swift"),',
        1,
    )
# Guard against accidental extra ')'
new = new.replace('.package(path: "../mlx-swift"))', '.package(path: "../mlx-swift")')
open(path, "w").write(new)
print("patched", path)
PY
fi

echo ""
echo "Done. StoryPromptKit Package.swift expects:"
echo "  $MLX_SWIFT"
echo "  $MLX_LM"
echo ""
echo "Open the Xcode project and resolve packages. Metal shaders for MLX must be built via Xcode."
echo "Model pack: prism-ml/Bonsai-27B-mlx-1bit (~5.13 GB) — download/import in app gate."
