# Vovozinha — agent notes

## Product
- Offline **kids bedtime stories** (~3–8); parents/caregivers **18+**.
- **No cloud AI** for generation.
- Floor: **iPhone 15+**. Story body requires **on-device LLM**:
  - **Foundation Models** when iOS 26+ + Apple Intelligence–capable hardware.
  - **Local LLM pack** for A16 / non-AI devices — **not shipped yet** (do not invent a template fallback).
- **UI + stories:** pt-BR / en-US / es-ES (language bar; default system).
- **Page art:** offline; **procedural** by default; **Core ML SD pack** when installed under `ImagePack/Resources`. Temporal chain: previous page → next (img2img / underlay). Fixed **10 pages**.
- **Story text pipeline:** one LLM call → title + summary + **exactly 10 scene paragraphs** (`StorySceneTags`: setup…bedtime) → each paragraph = one page. Images follow **that page’s scene text** (+ short hero lock for art only). Do not restate full actor appearance on every paragraph.
- **Prompt files:** edit static text under `Vovozinha/Resources/Prompts/` (loaded by `PromptCatalog`). Rebuild after edits.
- ~280 words total (band 150–480); kids filter **retry until pass**.
- Single actor (toy or kid): description (photo later).

## Build
```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```
Xcode 27 beta; deploy iOS 18+; sim iOS 27 for UI.

**Dev story invariant:** Create/Generate must **never** fail solely with “LLM unavailable” when
`DeviceProfile.allowsDevStoryFallback` is true:
- iOS Simulator
- **My Mac (Designed for iPad)** (`ProcessInfo.isiOSAppOnMac`) — *not* the same as Simulator
- Any **DEBUG** build
Uses `SimulatorDevStoryPlanner` (draft-parameterized offline story). **Release** on a real iPhone still requires FM/pack.

**Tabs:** Create (left) → Library → Settings. Launch: **Create** if no stories; **Library** if any exist.

## Code norms
- Prefer small, focused diffs.
- Product path: `FoundationModelsStoryPlanner` / `UnavailableLLMStoryPlanner` only — **never** reintroduce template/pre-written story planners into `makeDefault`.
- Persist **story language** on `Story`; TTS/PDF use it.
- Never surface raw system/FM English errors in UI — map via `StoryPlanningError` / L10n.
- Keep kids-safety prompts and filters intact.
- Character defaults must respect `input.language` (no PT bleed into EN/ES).
- **Narration 100% offline:** `AVSpeech` / future on-device voice packs only. Downloadable files OK; **never** cloud TTS or remote audio processing.
