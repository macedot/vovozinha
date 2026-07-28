# On-device story LLM — status & next swap

## Current status (branch `multi`)

| Item | Value |
|------|--------|
| **Backend** | MLX + `prism-ml/Bonsai-27B-mlx-1bit` (text only) |
| **Runtime** | Prism `mlx-swift` (1-bit) + `mlx-swift-lm` **@ 3.31.4** |
| **Pack path** | `Documents/Vovozinha/Models/Bonsai-27B-mlx-1bit/` |
| **Gate** | Download zip / Import folder|zip / HF fallback / halt |
| **Output contract** | `TITLE:` / `SUMMARY:` + **exactly 10** paragraphs |
| **Fallback stories** | **None** — missing model or bad parse → error |

### Device feedback

**Bonsai did not meet product quality on real-device tests** (quality / latency / memory — or combination). Treat it as a **trial stack to replace**, not the shipping model.

Do **not** invest further in Bonsai-specific tuning unless a new measurement shows otherwise. Prefer swapping to another on-device pack (LiteRT/Gemma again, smaller MLX, FM where available, etc.).

---

## Stable seams (keep across refactors)

These should stay put so a model swap is mostly delete/replace under one folder + Package deps:

| Seam | Role |
|------|------|
| `StoryFromPromptGenerating` | Feature boundary: seed → `StoryDraft` |
| `DeviceStoryGenerator` | Production entry; checks pack present, then delegates |
| `StoryPromptFeatureView` + model gate UI | Install UX (URLs/filename hints are the main churn) |
| `StoryPromptTemplate` + `litert.<lang>.md` | Prompt contract (rename files later if desired) |
| Parse: title / summary / 10 paragraphs | Shared by any generator (`MLXBonsaiStoryGenerator.parse` today) |
| `StoryPromptError.modelNotInstalled` / `.generationFailed` | UI mapping via L10n |

### Bonsai-specific (expected to go)

- `Packages/StoryPromptKit/.../Bonsai/*`
- `scripts/setup_bonsai_mlx.sh` and sibling `../mlx-swift`, `../mlx-swift-lm`
- Host/CDN URLs + L10n filename hints (~5 GB / Bonsai pack name)
- Package.swift products: MLX / MLXLLM / MLXVLM / MLXHuggingFace / Tokenizers

---

## Checklist for the next backend

1. **Commit** current tree first (rollback point).
2. Pick model: format (`.litertlm` vs MLX dir vs other), size, min device, license.
3. Implement **store** (download + import + `isModelPresent`) — mirror gate UX.
4. Implement **session** protocol + generator reusing **parse + prompts**.
5. Wire `DeviceStoryGenerator` + `StoryPromptFeatureView` to the new store.
6. Delete previous runtime deps, setup scripts, docs strings.
7. Unit tests with **mock session only**; live gen only on device.
8. Update README / AGENTS / MODULES / L10n pack hints.

### Product invariants (do not regress)

- No cloud generation / cloud TTS  
- No static/template story body  
- Fixed 10 pages / scenes  
- pt-BR / en-US / es-ES  
- Physical iPhone floor (Simulator unsupported)  

---

## Commits worth knowing

- `bbbb315` — LiteRT gate + kraftek Gemma download (pre-Bonsai)  
- `f5d32b4` — Replace LiteRT with Bonsai MLX  

Next model work should start with a new commit after this note lands.
