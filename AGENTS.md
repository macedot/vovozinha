# Vovozinha — agent notes

## Product
- Offline **kids bedtime stories** (~3–8); parents/caregivers **18+**.
- **No cloud AI** for generation.
- Floor: **iPhone 15+**. Story body requires **on-device LLM**:
  - **Foundation Models** when iOS 26+ + Apple Intelligence–capable hardware.
  - **Local LLM pack** for A16 / non-AI devices — **not shipped yet** (do not invent a template fallback).
- **UI + stories:** pt-BR / en-US / es-ES (language bar; default system).
- **Text-only phase:** `FeatureFlags.graphicsEnabled = false`; fixed **10 pages**.
- Method: whole continuous story → 10 descriptive paragraphs; ~280 words total (band 150–480); kids filter **retry until pass**.
- Single actor (toy or kid): photo and/or description.

## Build
```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```
Xcode 27 beta; deploy iOS 18+; sim iOS 27 for UI.

## Code norms
- Prefer small, focused diffs.
- Product path: `FoundationModelsStoryPlanner` / `UnavailableLLMStoryPlanner` only — **never** reintroduce template/pre-written story planners into `makeDefault`.
- Persist **story language** on `Story`; TTS/PDF use it.
- Never surface raw system/FM English errors in UI — map via `StoryPlanningError` / L10n.
- Keep kids-safety prompts and filters intact.
- Character defaults must respect `input.language` (no PT bleed into EN/ES).
- **Narration 100% offline:** `AVSpeech` / future on-device voice packs only. Downloadable files OK; **never** cloud TTS or remote audio processing.
