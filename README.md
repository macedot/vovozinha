# Vovozinha

Offline-first **children’s bedtime stories** for iOS (StoryKit-inspired): describe a character (optional photo) → on-device LLM story → text book with TTS and PDF.

| | |
|--|--|
| **Content** | Kids ~3–8 |
| **Who uses the app** | Parents / caregivers **18+** |
| **Devices** | **iPhone 15+** |
| **AI** | **Strictly on-device** (no cloud generation) |
| **Languages** | **pt-BR / en-US / es-ES** (language bar; default = system) |
| **This phase** | **Text-only** stories (illustrations deferred) |

## Story generation (this phase)

- **Body text:** local **LLM only** — Apple **Foundation Models** when available.
- **No** pre-written / template story body in the product path.
- **10 pages** = one continuous chronological story split into 10 paragraphs.
- Target **~280 words** total (band ~150–480); **3–5 short sentences per page** with sensory scene detail.
- **Kids content filter** with rewrite retries until pass.
- **Graphics / image models:** off (`FeatureFlags.graphicsEnabled = false`); local image pack later.

### Who can generate today

| Device / OS | Stories |
|-------------|---------|
| **iOS 26+** with **Apple Intelligence** (typically Pro-class / A17+) | **Yes** — Foundation Models |
| **iPhone 15 / 15 Plus (A16)** | **Not yet** — needs optional **local LLM pack** (stub; coming later) |
| Older / no FM assets | No — clear in-app message; no template fallback |
| Simulator | Usually no FM path; UI works |

## Dev requirements

| Item | Value |
|------|--------|
| macOS | Beta ok |
| Xcode | **Xcode 27 beta** (`/Applications/Xcode-beta.app`) |
| Deployment | iOS **18.0+**, iPhone only |
| Simulator | iOS 27 (e.g. iPhone 17) for UI |

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
open /Users/thiago/Projects/vovozinha/Vovozinha.xcodeproj
```

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Users/thiago/Projects/vovozinha
xcodebuild -scheme Vovozinha -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
```

## App flow

1. **18+** age gate  
2. Language bar (system / PT / EN / ES)  
3. **Quick create** — description + optional photo; rest randomized  
4. **Custom create** — full form (world, lesson, age, style, idea)  
5. **Generate** — character → on-device LLM story → library  
6. **Reader** — swipe text pages, TTS in story language, parent read-aloud, text PDF  
7. **Library** offline  

## Architecture (summary)

- SwiftUI + SwiftData  
- Protocols: `CharacterAnalyzing`, `StoryPlanning`, `Illustrating`  
- Product planner: `FoundationModelsStoryPlanner` or `UnavailableLLMStoryPlanner`  
- Scene beat labels: `StorySceneTags` (not a story body source)  
- Illustrator (`ProceduralKidsIllustrator`) present but **disabled** until a local image pack  

See `docs/SPIKE.md` and `AGENTS.md`.

## Privacy

Photos and stories stay under `Documents/Vovozinha/`. No account, no required analytics, **no cloud generation or cloud TTS**. Optional downloads (voice/model packs) only install files; synthesis stays on-device.
