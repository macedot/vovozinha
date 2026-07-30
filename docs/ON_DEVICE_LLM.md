# On-device story LLM — status & swap guide

## Current status (branch `multi`)

| Item | Value |
|------|--------|
| **Backend** | MLX + **mlx-community/Qwen3.5-4B-MLX-4bit** (text only) |
| **Runtime** | Local `mlx-swift` + `mlx-swift-lm` @ 3.31.4 (see `./scripts/setup_mlx_local.sh`) |
| **Pack path** | `Library/Application Support/Vovozinha/Models/Qwen3.5-4B-MLX-4bit/` (private; **not** Documents/Downloads) |
| **CDN zip** | `https://files.kraftek.dev/qwen/Qwen3.5-4B-MLX-4bit.zip` |
| **CDN checksum** | `https://files.kraftek.dev/qwen/Qwen3.5-4B-MLX-4bit.zip.sha256` (fetched before zip; host download only) |
| **Install hash** | Sibling sidecar `…/Models/Qwen3.5-4B-MLX-4bit.installed.sha256` after verified host download; compared to CDN on ready to offer a non-blocking update |
| **Remove model** | Clears Application Support pack + install hash; returns to needs-model gate |
| **Package zip** | `./scripts/package_qwen35_4b_mlx_zip.sh` → `build/Qwen3.5-4B-MLX-4bit.zip` + `.sha256` |
| **Gate** | Download zip / Import folder\|zip / HF fallback / halt |
| **PhotoDescribe** | Same pack via **`VLMModelFactory`** (vision weights kept); scheme **PhotoDescribeDebug** only — not in host yet |
| **Output contract** | `TITLE:` / `SUMMARY:` + **exactly 10** paragraphs |
| **Fallback stories** | **None** — missing model or bad parse → error |

---

## Stable seams (keep across refactors)

| Seam | Role |
|------|------|
| `StoryFromPromptGenerating` | Feature boundary: seed → `StoryDraft` |
| `DeviceStoryGenerator` | Production entry; checks pack present, then delegates |
| `StoryPromptFeatureView` + model gate UI | Install UX |
| `StoryPromptTemplate` + `story.<lang>.md` | Prompt contract |
| Parse in `MLXStoryGenerator` | title / summary / 10 paragraphs |
| `StoryPromptError.modelNotInstalled` / `.generationFailed` | UI mapping via L10n |

### Current MLX-specific types

- `Packages/StoryPromptKit/.../MLX/*` — `OnDeviceMLXModelStore`, `MLXStoryGenerator`, `MLXStoryEngineSession`
- Package deps: MLX, MLXLLM, MLXVLM, Tokenizers

---

## Packaging the CDN zip

```bash
./scripts/package_qwen35_4b_mlx_zip.sh
# → build/Qwen3.5-4B-MLX-4bit.zip + .sha256
# Upload BOTH to files.kraftek.dev/qwen/
# App downloads the .sha256 sidecar and verifies the zip against it.
# Do not commit the zip into git.
```

Packaging uses **`zip -0` (store)**: model weights are already compressed, so deflate
barely shrinks the archive and only slows device unpack. The app extracts with
**ZIPFoundation** (libcompression). Re-upload both the zip and `.sha256` after
repackaging — the checksum changes even when weights do not.

### Storage

| Asset | Location |
|-------|----------|
| **Model pack** | `Application Support/Vovozinha/Models/…` (private; excluded from backup). Host installs also write `….installed.sha256` beside the pack for update detection. |
| **Story exports** | `Documents/Vovozinha/Exports/` by default (`StoryExportLocationStore`; user can pick another folder) |

Legacy installs that still have the pack under `Documents/Vovozinha/Models/` are migrated
once into Application Support on first access.

### Product invariants

- No cloud generation / cloud TTS  
- No static/template story body  
- Fixed 10 pages / scenes  
- pt-BR / en-US / es-ES  
- Physical iPhone floor (Simulator unsupported)  
- Models never stored in user Documents or Downloads

---

## Memory budget (~3.8 GiB jetsam limit on 6 GB iPhones)

- **Text-only load (Story Prompt):** `MLXStoryEngineSession` loads through `LLMModelFactory` (falling back to
  `VLMModelFactory`). The LLM `Qwen3.5` `sanitize` drops the `vision_tower` weights
  (**~0.67 GB** of the pack) before they materialize — the story path never uses vision.
- **VLM load (Photo Describe):** `MLXPhotoDescribeSession` loads through `VLMModelFactory` so
  vision weights stay available for image captions. Heavier residency; same increased-memory entitlement.
- **Entitlement:** both app targets set `com.apple.developer.kernel.increased-memory-limit`
  (`Apps/Vovozinha/Vovozinha.entitlements`, `Apps/StoryPromptDebug/StoryPromptDebug.entitlements`)
  to raise the per-app limit.
- **MLX allocator:** `MLX.Memory.clearCache()` runs after every generation so cached Metal
  buffers return to the OS (the container is loaded per generation and dropped). If peak is
  still tight, the remaining knobs are `Memory.cacheLimit` (cap MLX's buffer hoard),
  `GenerateParameters.kvBits` (KV cache is small here — hybrid linear/full attention), and
  repacking the zip text-only (2.37 GB download instead of 3.03 GB).
