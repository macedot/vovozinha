# On-device story LLM — status & swap guide

## Current status (branch `multi`)

| Item | Value |
|------|--------|
| **Backend** | MLX + **mlx-community/Qwen3.5-4B-MLX-4bit** (text only) |
| **Runtime** | Local `mlx-swift` + `mlx-swift-lm` @ 3.31.4 (see `./scripts/setup_mlx_local.sh`) |
| **Pack path** | `Documents/Vovozinha/Models/Qwen3.5-4B-MLX-4bit/` |
| **CDN zip** | `https://files.kraftek.dev/qwen/Qwen3.5-4B-MLX-4bit.zip` |
| **CDN checksum** | `https://files.kraftek.dev/qwen/Qwen3.5-4B-MLX-4bit.zip.sha256` (fetched before zip; host download only) |
| **Package zip** | `./scripts/package_qwen35_4b_mlx_zip.sh` → `build/Qwen3.5-4B-MLX-4bit.zip` + `.sha256` |
| **Gate** | Download zip / Import folder\|zip / HF fallback / halt |
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

### Product invariants

- No cloud generation / cloud TTS  
- No static/template story body  
- Fixed 10 pages / scenes  
- pt-BR / en-US / es-ES  
- Physical iPhone floor (Simulator unsupported)  
