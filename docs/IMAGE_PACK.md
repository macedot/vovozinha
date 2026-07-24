# On-device anime image pack (Core ML)

Vovozinha stays **offline for inference**. Parents download model files once; then all page art runs on-device.

## Default pack (anime-tuned)

| | |
|--|--|
| **Model** | [Anything V5 Ink](https://huggingface.co/mozksoft/AnythingV5Ink-coreml) (anime SD1.5 fine-tune) |
| **Variant** | `split_einsum_v2` **compiled** (Neural Engine on iPhone) |
| **Size** | ~1.5 GB zip |
| **Img2img** | Yes (`VAEEncoder` included) |

This is **not** Apple’s generic photoreal SD1.5 base. It is an anime-oriented UNet that matches the app’s Japanese anime style prompts far better.

## What the app uses

| Component | Role |
|-----------|------|
| SPM `StableDiffusion` | [apple/ml-stable-diffusion](https://github.com/apple/ml-stable-diffusion) |
| `CoreMLDiffusionIllustrator` | text2img page 0 · **img2img** pages 1–9 from previous image |
| `ProceduralKidsIllustrator` | Fallback when pack missing / OOM |
| `SceneArtBrief` | Anime schema + locked hero + kids negative prompt |

## Install pack (preferred: in-app)

1. Open **Vovozinha → Settings → Anime image pack (Core ML)**  
2. Tap **Download anime scene pack** (~1.5 GB — use Wi‑Fi)  
3. Wait for download + extract until status says **Pack ready**  
4. Generate a story — first load is slow; later pages use img2img  

If you already installed the **legacy Apple SD1.5** pack, delete it in Settings and download again to switch to anime.

### Optional CLI (developer)

```bash
cd /Users/thiago/Projects/vovozinha
./scripts/download_sd_pack.sh
```

Legacy (not anime):

```bash
LEGACY=1 ./scripts/download_sd_pack.sh
```

Destination:

```
~/Library/Application Support/Vovozinha/ImagePack/Resources/
  TextEncoder.mlmodelc
  Unet.mlmodelc
  VAEDecoder.mlmodelc
  VAEEncoder.mlmodelc
  vocab.json
  merges.txt
pack.json   # marks pack as anime-anything-v5-ink
```

## Device notes

- **iPhone 15 Pro / A17+**: best experience (Neural Engine).
- **iPhone 15 / A16**: expect longer per-page time; `reduceMemory` stays on.
- First page after install may compile models (slow once).
- Anime models can be more “adult-looking” than kids clipart — the app keeps strong kids **negative** prompts and only illustrates soft bedtime scenes.

## Without the pack

Stories still generate. Art stays **procedural** — not anime quality.

## Temporal coherence

1. Same hero lock string every page.  
2. Shared story art seed.  
3. **Img2img** from previous page when `VAEEncoder` is present.  
4. Fixed kids + anti-photoreal **negative** prompt.  
5. Optional user photo on page 0.
