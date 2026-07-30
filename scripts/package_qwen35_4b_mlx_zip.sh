#!/usr/bin/env bash
# Download mlx-community/Qwen3.5-4B-MLX-4bit and pack a CDN-ready zip for
# https://files.kraftek.dev/qwen/Qwen3.5-4B-MLX-4bit.zip
#
# Usage (from repo root):
#   ./scripts/package_qwen35_4b_mlx_zip.sh
#
# Outputs (gitignored under .cache/ / build/):
#   .cache/models/Qwen3.5-4B-MLX-4bit/   unpacked pack
#   build/Qwen3.5-4B-MLX-4bit.zip
#   build/Qwen3.5-4B-MLX-4bit.zip.sha256
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_ID="${MODEL_ID:-mlx-community/Qwen3.5-4B-MLX-4bit}"
PACK_NAME="${PACK_NAME:-Qwen3.5-4B-MLX-4bit}"
CACHE_DIR="${CACHE_DIR:-$ROOT/.cache/models/$PACK_NAME}"
OUT_DIR="${OUT_DIR:-$ROOT/build}"
ZIP_PATH="$OUT_DIR/${PACK_NAME}.zip"
SHA_PATH="$OUT_DIR/${PACK_NAME}.zip.sha256"
CDN_URL="https://files.kraftek.dev/qwen/${PACK_NAME}.zip"

mkdir -p "$(dirname "$CACHE_DIR")" "$OUT_DIR"

echo "==> Pack: $PACK_NAME"
echo "==> Source: $MODEL_ID"
echo "==> Local dir: $CACHE_DIR"

download() {
  if command -v hf >/dev/null 2>&1; then
    hf download "$MODEL_ID" --local-dir "$CACHE_DIR"
  elif command -v huggingface-cli >/dev/null 2>&1; then
    huggingface-cli download "$MODEL_ID" \
      --local-dir "$CACHE_DIR" \
      --local-dir-use-symlinks False
  else
    echo "error: need 'hf' or 'huggingface-cli' (pip install huggingface_hub)" >&2
    exit 1
  fi
}

if [[ ! -f "$CACHE_DIR/config.json" ]]; then
  echo "==> Downloading model (several GB)…"
  download
else
  echo "==> Reusing existing $CACHE_DIR (delete to re-download)"
fi

# Validate MLX pack
if [[ ! -f "$CACHE_DIR/config.json" ]]; then
  echo "error: missing config.json in $CACHE_DIR" >&2
  exit 1
fi
if ! compgen -G "$CACHE_DIR/*.safetensors" >/dev/null; then
  echo "error: no *.safetensors in $CACHE_DIR" >&2
  exit 1
fi

echo "==> Building zip (store / -0) → $ZIP_PATH"
# Store method: 4-bit safetensors barely shrink under deflate, and max compression
# made iOS unpack painfully slow. Zip is slightly larger; device extract is mostly copy.
rm -f "$ZIP_PATH"
(
  cd "$(dirname "$CACHE_DIR")"
  # Folder name inside zip = PACK_NAME so app unpacker can find config.json one level deep.
  zip -r -0 "$ZIP_PATH" "$(basename "$CACHE_DIR")" \
    -x "*.DS_Store" \
    -x "**/.cache/**" \
    -x "**/.git/**" \
    -x "**/__pycache__/**"
)

HEX="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "$HEX  $(basename "$ZIP_PATH")" | tee "$SHA_PATH"
ls -lh "$ZIP_PATH"

echo ""
echo "Done."
echo "  Upload BOTH files to the CDN (app fetches the sidecar for integrity):"
echo "    $CDN_URL"
echo "    ${CDN_URL}.sha256"
echo "  App dir:    Application Support/Vovozinha/Models/${PACK_NAME}/"
echo "  Zip:        $ZIP_PATH"
echo "  SHA-256:    $SHA_PATH  ($HEX)"
echo ""
echo "Do not commit the zip into git."
