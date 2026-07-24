# SPIKE — Vovozinha local AI stack

## Current
| Stage | Implementation |
|-------|----------------|
| Story text | `FoundationModelsStoryPlanner` (on-device LLM) |
| Page art | `IllustratorFactory` → neural pack **or** `ProceduralKidsIllustrator` |
| Continuity | Shared `storyArtSeed` + **previous-page** underlay / img2img strength ~0.48 |
| Scene match | `SceneArtBrief` (locked hero, lighting arc, action, props, kids negative prompt) |

## Why procedural alone cannot match scenes
Procedural Core Graphics cannot parse free text into composition. It only uses keywords + palettes. True scene fidelity needs a **local diffusion model**.

## Recommended on-device image model
| Choice | Notes |
|--------|--------|
| **Best path** | [Apple Core ML Stable Diffusion](https://github.com/apple/ml-stable-diffusion) + HF preconverted **SD 1.5** (palettized / `split_einsum`) |
| **Speed** | SD-Turbo / LCM converted to Core ML (fewer steps) |
| **Avoid on iPhone** | Flux, full SDXL, cloud APIs |
| **Fallback** | Procedural (always offline) |

### Temporal coherence (required for 10-page books)
1. Same hero lock string every page (`CharacterProfile.lockedDescription`).  
2. Shared story seed; page seed = storySeed + index.  
3. **Page 0:** text2img (or procedural).  
4. **Pages 1–9:** **img2img** from previous image (strength ~0.4–0.5) when neural pack is live; procedural uses previous frame as underlay.  
5. Fixed kids **negative** prompt.  
6. Optional user photo on page 0.

### Pack layout (offline install)
```
Application Support/Vovozinha/ImagePack/Resources/
  TextEncoder.mlmodelc, Unet*.mlmodelc, VAEDecoder.mlmodelc, VAEEncoder.mlmodelc,
  vocab.json, merges.txt
```
- SPM: `apple/ml-stable-diffusion` → product `StableDiffusion` (**linked**).
- Install: `./scripts/download_sd_pack.sh` (see `docs/IMAGE_PACK.md`).
- Runtime: `CoreMLDiffusionIllustrator` when pack ready, else procedural.

## Constraints
- No cloud generation (text or images).  
- Download pack OK; inference on-device only.  
- iPhone 15+; A16 needs quantized SD1.5-class models.
