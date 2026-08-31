#!/usr/bin/env bash
# Convert a HuggingFace diffusers SD checkpoint to a CDN-ready Core ML image pack for
# on-device anime img2img (AnimeImg2Img-SD15 by default).
#
# Mirrors the conventions of package_qwen35_4b_mlx_zip.sh:
#   - zip -r -0  (store, no compression: .mlmodelc barely shrinks; deflate slows device unpack)
#   - shasum -a 256 sidecar in shasum text format ("HEX  filename")
#   - output under gitignored build/; upload BOTH files to vovo.kraftek.cloud
#
# Layout produced (matches CoreMLImagePackStore.directoryLooksLikeImagePack):
#   AnimeImg2Img-SD15/Resources/
#     TextEncoder.mlmodelc   VAEDecoder.mlmodelc   VAEEncoder.mlmodelc
#     UnetChunk1.mlmodelc    UnetChunk2.mlmodelc   (--chunk-unet; preferred for RAM)
#     vocab.json             merges.txt
#     pack.json              (manifest)
#   SafetyChecker.mlmodelc is deliberately dropped.
#
# Usage (from repo root, on a Mac):
#   ./scripts/package_anime_img2img_mlpackage.sh
#
# Env overrides:
#   MODEL_ID=genai-archive/anything-v5    diffusers-format SD1.5 anime checkpoint
#   PACK_NAME=AnimeImg2Img-SD15           top-level folder name inside the zip
#   BASE=sd15                             manifest marker (sd15 | sdxl)
#
# Outputs:
#   build/<PACK_NAME>.zip
#   build/<PACK_NAME>.zip.sha256
#
# NOTE: To switch to Animagine XL 4.0 later, set MODEL_ID=cagliostrolab/animagine-xl-4.0,
# add --convert-unet-maximum-sequence-length 512 to the torch2coreml call, set BASE=sdxl,
# and bump the bucket modelSize to 1024 in the app. SDXL reverses docs/SPIKE.md's
# "avoid full SDXL on iPhone" guidance — do that deliberately.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_ID="${MODEL_ID:-genai-archive/anything-v5}"
PACK_NAME="${PACK_NAME:-AnimeImg2Img-SD15}"
BASE="${BASE:-sd15}"
OUT_DIR="${OUT_DIR:-$ROOT/build}"
STAGE="$ROOT/.cache/imagepack/$PACK_NAME"
SD_CHECKOUT="$ROOT/.cache/ml-stable-diffusion"
VENV="$ROOT/.cache/venv-coreml"
RESOURCES="$STAGE/Resources"
ZIP_PATH="$OUT_DIR/${PACK_NAME}.zip"
SHA_PATH="$OUT_DIR/${PACK_NAME}.zip.sha256"
CDN_URL="https://vovo.kraftek.cloud/imagepack/${PACK_NAME}.zip"

mkdir -p "$OUT_DIR" "$STAGE"

echo "==> Pack:    $PACK_NAME (base: $BASE)"
echo "==> Source:  $MODEL_ID"
echo "==> Stage:   $STAGE"

# ---------------------------------------------------------------------------
# 1. Apple's converter (apple/ml-stable-diffusion) + Python deps in a venv.
#    setup.py lives at the *repo root*, not inside python_coreml_stable_diffusion/.
#    coremltools has no 3.14 wheels — prefer 3.11/3.12.
# ---------------------------------------------------------------------------
pick_python() {
  if [[ -n "${PYTHON:-}" ]]; then
    echo "$PYTHON"
    return
  fi
  local c
  for c in python3.11 python3.12 python3.10 \
           /Users/thiago/.local/bin/python3.11 \
           /opt/homebrew/bin/python3.12 \
           /opt/homebrew/bin/python3.11; do
    if command -v "$c" >/dev/null 2>&1 || [[ -x "$c" ]]; then
      echo "$c"
      return
    fi
  done
  echo "error: need Python 3.10–3.12 for coremltools (system python3 is $(python3 --version 2>&1))." >&2
  echo "       brew install python@3.11   or   PYTHON=/path/to/python3.11 $0" >&2
  exit 1
}

venv_python_ok() {
  [[ -x "$VENV/bin/python" ]] || return 1
  "$VENV/bin/python" - <<'PY'
import sys
sys.exit(0 if (3, 10) <= sys.version_info[:2] <= (3, 12) else 1)
PY
}

ensure_venv() {
  local py
  py="$(pick_python)"
  if venv_python_ok; then
    echo "==> Reusing venv at $VENV ($("$VENV/bin/python" -V))"
    return
  fi
  if [[ -d "$VENV" ]]; then
    echo "==> Recreating venv (was $("$VENV/bin/python" -V 2>/dev/null || echo 'broken'); need 3.10–3.12)"
    rm -rf "$VENV"
  fi
  echo "==> Creating venv at $VENV with $py ($("$py" -V))"
  "$py" -m venv "$VENV"
  "$VENV/bin/pip" install --upgrade pip wheel setuptools
}

ensure_converter() {
  if [[ -d "$SD_CHECKOUT/.git" && -f "$SD_CHECKOUT/setup.py" ]]; then
    echo "==> Reusing apple/ml-stable-diffusion checkout at $SD_CHECKOUT"
    return
  fi
  echo "==> Cloning apple/ml-stable-diffusion → $SD_CHECKOUT"
  rm -rf "$SD_CHECKOUT"
  mkdir -p "$(dirname "$SD_CHECKOUT")"
  git clone --depth 1 https://github.com/apple/ml-stable-diffusion.git "$SD_CHECKOUT"
}

patch_converter() {
  # Apple's torch2coreml always loads variant="fp16". Anything V5 (and many SD1.5
  # anime checkpoints) ship default-weight safetensors only. diffusers>=0.24
  # errors instead of falling back. Also drop use_auth_token (needs a HF login).
  local f="$SD_CHECKOUT/python_coreml_stable_diffusion/torch2coreml.py"
  python3 - "$f" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
orig = text
text = text.replace(',\n                                            variant="fp16"', "")
text = text.replace(',\n                                            use_auth_token=True', "")
if text == orig:
    # already patched, or upstream changed formatting — still try compact form
    text = text.replace(', variant="fp16"', "")
    text = text.replace(", variant=\"fp16\"", "")
    text = text.replace(", use_auth_token=True", "")
if "variant=" in text.split("def get_pipeline", 1)[-1].split("def main", 1)[0]:
    sys.stderr.write("warning: get_pipeline still mentions variant= after patch\n")
p.write_text(text)
print("patched", p)
PY
}

ensure_venv
ensure_converter
patch_converter

echo "==> Installing python_coreml_stable_diffusion from $SD_CHECKOUT (repo root setup.py)"
# Apple's setup.py pins numpy<1.24. That pulls scipy 1.15 wheels which fail to
# dlopen on macOS 27 (`__DATA/__thread_bss`). Install the converter *without*
# deps, then a stack that actually imports on this OS.
"$VENV/bin/pip" install --no-deps -e "$SD_CHECKOUT"
"$VENV/bin/pip" install \
  'numpy>=1.26,<2.3' \
  'scipy>=1.16' \
  'coremltools>=8.0' \
  'torch' \
  'transformers==4.44.2' \
  'huggingface-hub==0.24.6' \
  'diffusers[torch]==0.30.2' \
  'diffusionkit==0.4.0' \
  'safetensors' \
  'scikit-learn' \
  'invisible-watermark' \
  'matplotlib' \
  'pytest'
"$VENV/bin/python" -c "import python_coreml_stable_diffusion.torch2coreml" \
  || { echo "error: converter import failed" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 2. Convert. torch2coreml writes .mlpackage files to -o, then
#    --bundle-resources-for-swift-cli compiles them to -o/Resources/*.mlmodelc
#    and fetches vocab.json + merges.txt. --convert-vae-encoder is mandatory
#    for img2img; --chunk-unet lowers peak RAM; SPLIT_EINSUM_V2 is ANE.
# ---------------------------------------------------------------------------
CONVERT_OUT="$STAGE/mlpackages"
if [[ ! -d "$RESOURCES/TextEncoder.mlmodelc" ]]; then
  echo "==> Converting $MODEL_ID → Core ML (this takes several minutes)…"
  rm -rf "$RESOURCES" "$CONVERT_OUT"
  mkdir -p "$CONVERT_OUT"
  "$VENV/bin/python" -m python_coreml_stable_diffusion.torch2coreml \
    --convert-vae-encoder \
    --convert-vae-decoder \
    --convert-unet \
    --convert-text-encoder \
    --chunk-unet \
    --attention-implementation SPLIT_EINSUM_V2 \
    --bundle-resources-for-swift-cli \
    --model-version "$MODEL_ID" \
    -o "$CONVERT_OUT"
  if [[ -d "$CONVERT_OUT/Resources" ]]; then
    rm -rf "$RESOURCES"
    mv "$CONVERT_OUT/Resources" "$RESOURCES"
  fi
  # mlpackages are intermediates; the app pack is compiled .mlmodelc only.
  rm -rf "$CONVERT_OUT"
else
  echo "==> Reusing existing $RESOURCES (delete to re-convert)"
fi

# ---------------------------------------------------------------------------
# 3. Validate + normalize the staged layout.
# ---------------------------------------------------------------------------
echo "==> Validating staged pack"
require() {
  local target="$RESOURCES/$1"
  if [[ ! -e "$target" ]]; then
    echo "error: missing $1 in $RESOURCES" >&2
    exit 1
  fi
}
require "TextEncoder.mlmodelc"
require "VAEDecoder.mlmodelc"
require "VAEEncoder.mlmodelc"   # mandatory for img2img
require "vocab.json"
require "merges.txt"
if [[ ! -d "$RESOURCES/Unet.mlmodelc" ]] \
  && { [[ ! -d "$RESOURCES/UnetChunk1.mlmodelc" ]] || [[ ! -d "$RESOURCES/UnetChunk2.mlmodelc" ]]; }; then
  echo "error: need Unet.mlmodelc or both UnetChunk1+UnetChunk2.mlmodelc" >&2
  exit 1
fi

# Drop SafetyChecker (we never use it; reduceMemory + disableSafety handle safety policy).
rm -rf "$RESOURCES/SafetyChecker.mlmodelc"
# Keep chunked Unet only — the full Unet.mlmodelc is a 1.6 GB duplicate.
if [[ -d "$RESOURCES/UnetChunk1.mlmodelc" && -d "$RESOURCES/UnetChunk2.mlmodelc" ]]; then
  rm -rf "$RESOURCES/Unet.mlmodelc"
fi

# Write the manifest (JSON). installedAt is filled by the device; here we record provenance.
cat > "$STAGE/pack.json" <<JSON
{
  "id": "$PACK_NAME",
  "repoID": "$MODEL_ID",
  "base": "$BASE",
  "displayName": "Anime Img2Img (SD1.5)",
  "zipFileName": "$(basename "$ZIP_PATH")"
}
JSON

echo "==> Staged files:"
( cd "$STAGE" && find . -maxdepth 2 -name '*.mlmodelc' -o -maxdepth 1 -name 'vocab.json' -o -maxdepth 1 -name 'merges.txt' -o -maxdepth 1 -name 'pack.json' | sort )

# ---------------------------------------------------------------------------
# 4. Zip (store / -0) + sha256 sidecar.
# ---------------------------------------------------------------------------
echo "==> Building zip (store / -0) → $ZIP_PATH"
rm -f "$ZIP_PATH"
(
  cd "$STAGE/.."
  # Top-level folder inside the zip = PACK_NAME; the app unpacker locates Resources/ within.
  # We archive the PACK_NAME folder, which contains Resources/ + pack.json.
  zip -r -0 "$ZIP_PATH" "$(basename "$STAGE")" \
    -x "*.DS_Store" \
    -x "**/__pycache__/**" \
    >/dev/null
)

HEX="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "$HEX  $(basename "$ZIP_PATH")" | tee "$SHA_PATH"
ls -lh "$ZIP_PATH"

echo ""
echo "Done."
echo "  Upload BOTH files to the CDN (app fetches the sidecar for integrity):"
echo "    $CDN_URL"
echo "    ${CDN_URL}.sha256"
echo "  App dir:    Application Support/Vovozinha/ImagePack/Resources/"
echo "  Zip:        $ZIP_PATH"
echo "  SHA-256:    $SHA_PATH  ($HEX)"
echo ""
echo "Do not commit the zip into git."
