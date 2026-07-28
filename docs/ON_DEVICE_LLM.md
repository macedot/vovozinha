# On-device story LLM — status & swap guide

## Current status (branch `multi`)

| Item | Value |
|------|--------|
| **Backend** | MLX + **mlx-community/Qwen3.5-4B-MLX-4bit** (text only) |
| **Runtime** | stock `ml-explore/mlx-swift` + `mlx-swift-lm` (≥ 3.31.3) |
| **Pack path** | `Documents/Vovozinha/Models/Qwen3.5-4B-MLX-4bit/` |
| **CDN zip** | `https://files.kraftek.dev/qwen/Qwen3.5-4B-MLX-4bit.zip` |
| **Package zip** | `./scripts/package_qwen35_4b_mlx_zip.sh` → `build/Qwen3.5-4B-MLX-4bit.zip` |
| **Gate** | Download zip / Import folder\|zip / HF fallback / halt |
| **Output contract** | `TITLE:` / `SUMMARY:` + **exactly 10** paragraphs |
| **Fallback stories** | **None** — missing model or bad parse → error |

### Retired trial

**Bonsai-27B-mlx-1bit** did not meet quality on device tests and was replaced by Qwen3.5-4B.

---

## Stable seams (keep across refactors)

| Seam | Role |
|------|------|
| `StoryFromPromptGenerating` | Feature boundary: seed → `StoryDraft` |
| `DeviceStoryGenerator` | Production entry; checks pack present, then delegates |
| `StoryPromptFeatureView` + model gate UI | Install UX |
| `StoryPromptTemplate` + `litert.<lang>.md` | Prompt contract |
| Parse in `MLXStoryGenerator` | title / summary / 10 paragraphs |
| `StoryPromptError.modelNotInstalled` / `.generationFailed` | UI mapping via L10n |

### Current MLX-specific types

- `Packages/StoryPromptKit/.../MLX/*` — `OnDeviceMLXModelStore`, `MLXStoryGenerator`, `MLXStoryEngineSession`
- Package deps: MLX, MLXLLM, MLXVLM, MLXHuggingFace, Tokenizers

---

## Packaging the CDN zip

```bash
./scripts/package_qwen35_4b_mlx_zip.sh
# → build/Qwen3.5-4B-MLX-4bit.zip (+ .sha256)
# Upload to files.kraftek.dev/qwen/
# Do not commit the zip into git.
```

### Product invariants

- No cloud generation / cloud TTS  
- No static/template story body  
- Fixed 10 pages / scenes  
- pt-BR / en-US / es-ES  
- Physical iPhone floor (Simulator unsupported)  
