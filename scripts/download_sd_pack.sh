#!/usr/bin/env bash
# Download the anime-tuned Core ML Stable Diffusion pack for Vovozinha.
# After install, inference is fully offline.
#
# Default: Anything V5 Ink (split_einsum_v2 compiled, includes VAEEncoder)
#   mozksoft/AnythingV5Ink-coreml
#
# Usage:
#   ./scripts/download_sd_pack.sh
#   REPO_ID=mozksoft/AnythingV5Ink-coreml ZIP=AnythingV5Ink-coreml_split_einsum_v2_compiled.zip ./scripts/download_sd_pack.sh
#
# Legacy Apple base SD1.5 (not anime):
#   LEGACY=1 ./scripts/download_sd_pack.sh

set -euo pipefail

if [[ "${LEGACY:-0}" == "1" ]]; then
  REPO_ID="${REPO_ID:-apple/coreml-stable-diffusion-v1-5-palettized}"
  VARIANT="${VARIANT:-split_einsum_v2/compiled}"
  MODE="tree"
else
  REPO_ID="${REPO_ID:-mozksoft/AnythingV5Ink-coreml}"
  ZIP_NAME="${ZIP:-AnythingV5Ink-coreml_split_einsum_v2_compiled.zip}"
  MODE="zip"
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="${ROOT}/.cache/venv-hf"
CACHE="${ROOT}/.cache/sd_pack"
APP_SUPPORT="${HOME}/Library/Application Support/Vovozinha/ImagePack"
DEST_RESOURCES="${APP_SUPPORT}/Resources"
DL_ROOT="${CACHE}/download"

echo "==> Vovozinha image pack installer"
echo "    mode:    ${MODE}"
echo "    repo:    ${REPO_ID}"
echo "    dest:    ${DEST_RESOURCES}"

mkdir -p "${CACHE}" "${DEST_RESOURCES}" "${DL_ROOT}"

if [[ ! -x "${VENV}/bin/python" ]]; then
  echo "==> Creating Python venv at ${VENV}"
  python3 -m venv "${VENV}"
fi
# shellcheck disable=SC1091
source "${VENV}/bin/activate"
python -m pip install -q --upgrade pip
python -m pip install -q "huggingface_hub>=0.23"

if [[ "${MODE}" == "zip" ]]; then
  echo "==> Downloading anime zip: ${ZIP_NAME}"
  export HF_REPO_ID="${REPO_ID}"
  export HF_ZIP="${ZIP_NAME}"
  export HF_DL_ROOT="${DL_ROOT}"
  python - <<'PY'
import os
from pathlib import Path
from huggingface_hub import hf_hub_download

repo = os.environ["HF_REPO_ID"]
zip_name = os.environ["HF_ZIP"]
out = Path(os.environ["HF_DL_ROOT"])
out.mkdir(parents=True, exist_ok=True)
path = hf_hub_download(
    repo_id=repo,
    filename=zip_name,
    local_dir=str(out),
    local_dir_use_symlinks=False,
)
print("zip at", path)
PY
  ZIP_PATH="${DL_ROOT}/${ZIP_NAME}"
  if [[ ! -f "${ZIP_PATH}" ]]; then
    # hf_hub_download may nest under snapshots
    ZIP_PATH=$(find "${DL_ROOT}" -name "${ZIP_NAME}" | head -1 || true)
  fi
  if [[ -z "${ZIP_PATH}" || ! -f "${ZIP_PATH}" ]]; then
    echo "ERROR: zip not found after download"
    exit 1
  fi
  echo "==> Extracting ${ZIP_PATH}"
  EXTRACT="${CACHE}/extract_tmp"
  rm -rf "${EXTRACT}"
  mkdir -p "${EXTRACT}"
  unzip -q "${ZIP_PATH}" -d "${EXTRACT}"
  # Find folder with TextEncoder.mlmodelc
  SRC=$(find "${EXTRACT}" -type d -name "TextEncoder.mlmodelc" | head -1 | xargs dirname)
  if [[ -z "${SRC}" || ! -d "${SRC}" ]]; then
    echo "ERROR: TextEncoder.mlmodelc not found in zip"
    exit 1
  fi
  echo "==> Installing from ${SRC}"
  rm -rf "${DEST_RESOURCES}"
  mkdir -p "${DEST_RESOURCES}"
  # Skip SafetyChecker if present
  rsync -a --exclude 'SafetyChecker.mlmodelc' "${SRC}/" "${DEST_RESOURCES}/"
  # Manifest
  cat > "${APP_SUPPORT}/pack.json" <<EOF
{"id":"anime-anything-v5-ink","repoID":"${REPO_ID}","zipFileName":"${ZIP_NAME}","displayName":"Anything V5 Ink (anime)","installedAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF
else
  # Legacy tree download (Apple SD1.5)
  export HF_REPO_ID="${REPO_ID}"
  export HF_DL_ROOT="${DL_ROOT}"
  download_variant() {
    local variant="$1"
    export HF_VARIANT="${variant}"
    echo "==> Downloading ${REPO_ID}  pattern: ${variant}/**"
    python - <<'PY'
import os
from pathlib import Path
from huggingface_hub import snapshot_download
repo = os.environ["HF_REPO_ID"]
variant = os.environ["HF_VARIANT"]
out = Path(os.environ["HF_DL_ROOT"])
path = snapshot_download(
    repo_id=repo,
    allow_patterns=[f"{variant}/*", f"{variant}/**"],
    local_dir=str(out),
    local_dir_use_symlinks=False,
)
print("snapshot at", path)
PY
  }
  find_resources_dir() {
    local found parent
    found=$(find "${DL_ROOT}" -type d -name "TextEncoder.mlmodelc" 2>/dev/null \
      | grep -v '/\.cache/huggingface/' \
      | head -1 || true)
    if [[ -z "${found}" ]]; then return 1; fi
    parent=$(dirname "${found}")
    if [[ -s "${parent}/vocab.json" && -s "${parent}/merges.txt" ]]; then
      echo "${parent}"; return 0
    fi
    return 1
  }
  SRC=""
  for v in "${VARIANT}" "split_einsum_v2/compiled" "split_einsum/compiled" "original/compiled"; do
    if download_variant "${v}"; then
      if SRC=$(find_resources_dir); then
        echo "==> Found resources at: ${SRC}"
        break
      fi
    fi
  done
  if [[ -z "${SRC}" ]]; then
    echo "ERROR: could not locate Core ML resources"
    exit 1
  fi
  rm -rf "${DEST_RESOURCES}"
  mkdir -p "${DEST_RESOURCES}"
  rsync -a "${SRC}/" "${DEST_RESOURCES}/"
fi

echo "==> Pack contents:"
ls -la "${DEST_RESOURCES}" | head -40

need() {
  local name="$1"
  if [[ -d "${DEST_RESOURCES}/${name}" ]] || [[ -f "${DEST_RESOURCES}/${name}" ]]; then
    echo "  OK  ${name}"; return 0
  fi
  echo "  MISSING  ${name}"; return 1
}

echo "==> Validation:"
ok=1
need "TextEncoder.mlmodelc" || ok=0
need "VAEDecoder.mlmodelc" || ok=0
need "vocab.json" || ok=0
need "merges.txt" || ok=0
if [[ -d "${DEST_RESOURCES}/Unet.mlmodelc" ]]; then
  need "Unet.mlmodelc" || ok=0
elif [[ -d "${DEST_RESOURCES}/UnetChunk1.mlmodelc" && -d "${DEST_RESOURCES}/UnetChunk2.mlmodelc" ]]; then
  need "UnetChunk1.mlmodelc" || ok=0
  need "UnetChunk2.mlmodelc" || ok=0
else
  echo "  MISSING  Unet.mlmodelc (or UnetChunk1+UnetChunk2)"; ok=0
fi
if [[ -d "${DEST_RESOURCES}/VAEEncoder.mlmodelc" ]]; then
  echo "  OK  VAEEncoder.mlmodelc  (img2img continuity enabled)"
else
  echo "  WARN VAEEncoder.mlmodelc missing — page-to-page img2img limited"
fi

if [[ "${ok}" -ne 1 ]]; then
  echo "ERROR: pack incomplete."
  exit 1
fi

echo ""
echo "Done. Pack ready at:"
echo "  ${DEST_RESOURCES}"
echo "In Settings, status should show the anime neural pack."
echo "First generation loads models (slow once); later pages use img2img when VAEEncoder is present."
