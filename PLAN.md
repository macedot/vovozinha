# Vovozinha — Unified On-Device Storybook App: Build Plan

> **Status:** Planning (supersedes `OLD/AGENTS.md`, `OLD/README.md`, `OLD/docs/*`)
> Everything that exists in the repo today has been moved to `OLD/` and is treated as
> **reference / inspiration only**. The final app is built fresh at the repo root,
> harvesting the good parts of `OLD/`.

---

## 1. Goal

Vovozinha is a fully **offline** iOS app that turns a short text idea — and optionally a
photo — into an illustrated **10-page bedtime storybook** for kids:

1. Parent types a short description (10–20 words) in pt-BR, en-US, or es-ES.
2. Optionally picks a photo from their library.
3. An on-device LLM (Qwen3.5-4B MLX 4-bit, served from our own CDN) writes a story:
   title, summary, and exactly 10 page texts. If a photo was provided, a vision pass
   describes it first and its elements are woven into the story.
4. Every page gets an illustration rendered **on-device** with Core ML Stable Diffusion
   (AnimeImg2Img-SD15 pack):
   - **Photo provided** → two-stage, coherence-first:
     a. **Reference pass (once per story):** the ORIGINAL photo is img2img-transformed
        into a **cartoonified character/element reference** — the photo's people,
        objects and setting redrawn once in the book's locked kids art style.
     b. **Page passes:** that cartoonified reference (not the raw photo) is the
        img2img base for **every** page, so the same characters/elements recur
        recognizably across all 10 pages.
   - **No photo** → txt2img per page from the locked kids-style prompt.
   - Style stays consistent across pages (fixed per-story seed + fixed style prefix +
     locked negative prompt + the shared cartoonified reference).

   **Temporal & element coherence — in both the text and the images — is a
   top-priority product requirement** (invariant 9, §9).
5. Story text appears immediately; illustrations render **asynchronously in page
   order** and fill in one by one. The book can be read, saved to the Library,
   shared, and exported (PDF).

**Hard rules:** no cloud inference, no cloud TTS, no static/template story bodies,
no fabrication fallbacks (parse failures are errors), physical-device-only testing
(**never the simulator**).

---

## 2. Decisions already locked (with Thiago)

| Decision | Value |
|---|---|
| Illustration UX | Text first; illustrations generated **async, in page order** (1→10), filling into the reader as they complete |
| No-photo path | **txt2img** from the style prompt (requires adding a txt2img mode to the image generator) |
| Model CDN | **`vovo.kraftek.cloud` only.** Remove `files.kraftek.dev` URLs and the Hugging Face fallback page from the apps. Offline **document-picker Import** remains as the manual fallback |
| Qwen zip URL | `https://vovo.kraftek.cloud/qwen/Qwen3.5-4B-MLX-4bit.zip` (+ `.sha256` sidecar) |
| Image pack URL | `https://vovo.kraftek.cloud/imagepack/AnimeImg2Img-SD15.zip` (+ `.sha256` sidecar) — path chosen by us; Thiago will upload the files |
| Git | `OLD/` move is the baseline; fresh app built at root. Branch/commit when ready |
| Testing | Connected physical iPhone only (same as Walker / inas) |

---

## 3. What exists today (`OLD/` inventory & verdict)

### 3.1 Packages (all `swift-tools-version: 6.0`, iOS 18 + macOS 14, all well-tested)

| Package | Verdict | Notes |
|---|---|---|
| `OLD/Packages/VovoUI` | **Port as-is** | Dark theme (`VovoTheme.deepNight`), `VovoScreen`, `LanguageBar`, `LanguageStore`, `VovoL10n`, button styles. Markdown string tables for pt-BR / en-US / es-ES. No external deps. |
| `OLD/Packages/StoryPromptKit` | **Port, then extend** | Story seed validation (10–20 words), `StoryFromPromptGenerating` protocol, `DeviceStoryGenerator`, `MLXStoryGenerator` (strips Qwen `<think>` blocks; parses `TITLE:`/`SUMMARY:`/exactly 10 paragraphs — never pads), `MLXStoryEngineSession` (loads per-generation via `LLMModelFactory.shared`, drops `vision_tower` ~0.67 GB, temp 0.7 / topP 0.95 / topK 20 / maxTokens 1536, `MLX.Memory.clearCache()` after each run), `OnDeviceMLXModelStore` (869-line actor: sidecar-first sha256 fetch → multi-GB download → hash verify → unzip → pack validation → installed-hash sidecar, document-picker import, update check, legacy migration). Depends on local sibling forks `../../../mlx-swift` + `../../../mlx-swift-lm` (Prism mlx-swift, mlx-swift-lm @ 3.31.4), `swift-transformers` 1.1.0+, `ZIPFoundation`, VovoUI. See §12.9, §12.25. |
| `OLD/Packages/PhotoDescribeKit` | **Port as-is** | `PhotoDescribing` protocol, `DevicePhotoDescriber`, VLM session via `VLMModelFactory` (keeps vision weights), 512×512 image resize, temp 0.4 / maxTokens 320. Reuses StoryPromptKit's `OnDeviceMLXModelStore` for the same Qwen pack (dependency-clean). `PhotosPicker`-based UI with the same gate-state machine. |
| `OLD/Packages/ImageGenKit` | **Port, then extend** | `ImageGenerating` protocol, `DeviceImageGenerator` (img2img only today), `PipelineCache` actor (`.cpuAndNeuralEngine`, `reduceMemory: true`, safety disabled, lazy load, refuses to load unless `os_proc_available_memory() ≥ 900 MB`), `CoreMLImagePackStore` (same download/verify/import machinery as the MLX store, deliberately duplicated due to the dependency conflict — see §6), `ImageGenConfig` (strength 0.6, 25 steps, CFG 6.0, `.dpmSolverMultistep` or `.pndm`, square/portrait/landscape 512-class buckets, random or fixed seed), locked kids negative prompt from `img2img.<lang>.md`. Depends on `apple/ml-stable-diffusion` 1.1.1 which **pins swift-transformers == 0.1.8** → this is THE blocker for combining with the MLX stack (§6). |
| `Packages/StorybookKit` (new) | **Create** | The unified pipeline orchestrator (§5). Depends on all three kits + VovoUI. |

### 3.2 Apps

- `OLD/Apps/Vovozinha` — host app today is just `StoryPromptFeatureView` in a
  NavigationStack + increased-memory entitlement (`com.apple.developer.kernel.increased-memory-limit`).
  **Replace** with the unified app; **keep the entitlement**.
- `OLD/Apps/StoryPromptDebug`, `Apps/PhotoDescribeDebug`, `Apps/ImageGenDebug` —
  one-file debug harnesses per feature. Useful while porting; keep out of the new
  project initially, re-create only if needed.
- `OLD/Apps/VovozinhaUITests` + `VovozinhaTests/` — XCUITests with stable
  accessibility IDs (`storySeedField`, `createStoryButton`, `storyResult`,
  `modelGateDownload`, `modelGateImport`, …). **Harvest the ID scheme and test
  structure.**

### 3.3 Reference-only (do not port)

- `OLD/Legacy/` — old Gemma/LiteRT-era app (static-story patterns, HF API downloader).
  Only mine it for the **age gate** view and export-location conventions.
- `OLD/docs/` — `MODULES.md`, `ON_DEVICE_LLM.md`, `ON_DEVICE_IMG2IMG.md`, `IMAGE_PACK.md`:
  re-read before porting; they document the constraints summarized in this file.
- `OLD/scripts/` — `package_qwen35_4b_mlx_zip.sh`, `package_anime_img2img_mlpackage.sh`
  (`--chunk-unet --split-einsum-v2`), `setup_mlx_local.sh` (clones sibling forks),
  `build_all.sh`, `gen_pbx.py`. **Keep** (update URLs/paths), reuse the packagers.
- `OLD/Vovozinha.xcodeproj` — superseded; the new project is generated fresh
  (decision pending: XcodeGen `project.yml` like Walker, or the existing pbx generator).

### 3.4 Environment facts (verified)

- Team **`FTS4YLJNG3`**, automatic signing (same across walker/inas/vovozinha).
- Xcode: only `/Applications/Xcode-beta.app` exists (Xcode 27 beta) → set
  `DEVELOPER_DIR` explicitly in all scripts.
- Physical device: **iPhone 15 Pro Max**, name `iPhone`, UDID
  **`00008130-001C78EC18EB8D3A`**, iOS 27.0 (24A5424a), Developer Mode ON, connected
  wired. Destination string: `platform=iOS,id=00008130-001C78EC18EB8D3A`.
- inas' `Scripts/test.sh` is the canonical device-test pattern to replicate
  (devicectl pre-check → hard fail if not connected → `xcodebuild test`).

---

## 4. Target architecture

### 4.1 Repo layout (fresh, at root)

```
Vovozinha.xcodeproj            (new)
project.yml                    (optional: XcodeGen, like walker)
Apps/Vovozinha/                (host app: thin composition only)
Packages/VovoUI/               (ported)
Packages/StoryPromptKit/       (ported + extended)
Packages/PhotoDescribeKit/     (ported)
Packages/ImageGenKit/          (ported + txt2img + forked dependency)
Packages/StorybookKit/         (new orchestrator)
Scripts/                       (deploy.sh, test.sh, setup_mlx_local.sh, packagers)
docs/                          (fresh docs; PLAN.md stays at root)
OLD/                           (reference, never imported)
```

Sibling MLX checkouts stay where they are (`~/Projects/mlx-swift`, `~/Projects/mlx-lm`);
the ported packages keep the same relative depth so `../../../mlx-swift` path deps
keep resolving.

### 4.2 Package dependency graph (after Phase 2 resolves the conflict)

```
VovoUI ← StoryPromptKit ← PhotoDescribeKit
   ↑            │
   │            ▼
   └──── StorybookKit ←──── ImageGenKit   (ml-stable-diffusion via our fork)
             ↑
        Apps/Vovozinha (links VovoUI + StorybookKit only)
```

Host stays thin: navigation, SwiftData persistence, settings. All logic lives in kits.

### 4.3 StorybookKit pipeline (new)

```
SeedPipeline.run(seed, photo?, language) -> AsyncStream<PipelineEvent>

  [gate]  both packs installed? (else surface gate UI states)
  [1]     photo? -> PhotoDescribing.describe(photo) -> PhotoCaption
          (caption feeds BOTH tracks: text coherence + the cartoonify reference prompt)
  [2]     StoryFromPromptGenerating.generate(seed, imageContext: caption?)
          -> StoryDraft { title, summary, 10 paragraphs }   (MLX)
          Caption elements are woven into the story so text and images stay coherent.
  [3]     IllustrationPromptGenerator.generate(draft, caption?)
          -> [String] (10 short prompts, numbered-line parse; lenient)
          -> pages enumerated into StoryPage { index, text, illustrationPrompt, image: nil }
          All 10 prompts embed the SAME locked character-descriptor string (derived
          once from the caption) so the cast is described identically on every page.
  [---]   MLX released here (after [3], never before) — see MemorySequencer
  [4]     photo? -> ImageGenerating.generate(referencePrompt, img2img(ORIGINAL photo),
          seed: baseSeed) -> CartoonReference (ONE render, persisted per story)
          The original photo's elements, cartoonified into the locked kids style.
          This reference — not the raw photo — anchors every page that follows.
  [5]     for page in pages (strict order, one render at a time):
            ImageGenerating.generate(prompt, config)   // img2img(CartoonReference) | txt2img
            -> yield .illustrationReady(page)
  [6]     yield .finished(storybook)
```

Events: `.pageTextsReady(pages)`, `.illustrationReady(page, index)`, `.phaseChanged`,
`.progress(step,of:steps)`, `.failed(error)`, `.finished`.

**Memory discipline (critical):** Qwen (~2.4 GB resident) and the SD pipeline
(~1 GB+) must never be resident together. Sequence: caption pass → story pass →
illustration-prompt pass → explicitly release MLX (drop session container,
`MLX.Memory.clearCache()`, verify `LLMModelFactory` cache doesn't retain — add
explicit unload if needed) → load Core ML pipeline (already guarded by the 900 MB
floor) → cartoonify reference (step [4]) → page render loop → release pipeline.
The strict page-order, one-at-a-time render loop is also what keeps memory flat.

**Consistency recipe per story (temporal & element coherence, text + image):**
- `baseSeed = UInt32(stableSHA256(storyID))` — **never** Swift's `hashValue`
  (per-process randomized; see §12.3); page seed = `baseSeed + page.index`.
- Style prefix from `img2img.<lang>.md ## positive` + locked negative scaffold,
  identical on every render.
- **Text coherence:** the photo caption's elements are woven into the story body
  (step [2]); the IllustrationPromptGenerator derives ONE locked
  character-descriptor string from the caption and embeds it verbatim in all 10
  illustration prompts (step [3]).
- **Image coherence:** the ORIGINAL photo is cartoonified exactly once (step [4])
  into a per-story `CartoonReference` (persisted alongside the book); every page
  render uses that reference as its img2img base, so the cast/elements stay
  visually the same from page 1 to 10.
- Strength default 0.6 for the reference pass; page passes likely lower
  (0.45–0.55) so scene prompts can diverge from the base — tuned in the Phase 3
  spike (§12.4).

### 4.4 Persisted model (host, SwiftData)

```
Storybook { id, title, summary, language, seedPrompt, photoThumb?, createdAt }
StoryPage  { index, text, illustrationPrompt, imageFileURL? }
```
Images as files under `Documents/Vovozinha/Stories/<storyID>/page-N.png`
(parent-exportable per the storage rules from `OLD/docs/ON_DEVICE_LLM.md`).
The cartoonified reference (§4.3 step [4]) is persisted as
`Documents/Vovozinha/Stories/<storyID>/reference.png` — it enables pipeline resume
(§12.1) and keeps re-renders of any page coherent with the rest of the book.
Model packs stay in `Application Support/Vovozinha/...` (backup-excluded, never in
Documents).

### 4.5 Host UI

- **Age gate** (first launch, 18+ parent acknowledgment — port view from `OLD/Legacy`).
- **Create** — language bar, seed field (live 10–20 word validation), PhotosPicker
  (optional), single model-gate screen covering **both** packs (Qwen ~3 GB zip +
  image pack ~1.5 GB zip: progress, speed/ETA, sha256 verify, Import button), then
  pipeline progress → jumps to Reader as soon as page texts are ready.
- **Reader** — 10 pages; text immediately; illustration slots show per-page
  progress and fill in order; share/save page PNG; export whole book as PDF;
  auto-saved to Library.
- **Library** — saved books (SwiftData), reopen/export/delete.
- **Settings** — language, pack status for both packs (version via installed-hash
  sidecar, update check, remove), export location, credits/about.
- Keep the accessibility-ID conventions from `OLD/Apps/VovozinhaUITests`; all new
  copy goes into the three Markdown string tables (no hardcoded strings).

---

## 5. Server deliverables (files for Thiago to upload)

| URL | File | Built by |
|---|---|---|
| `https://vovo.kraftek.cloud/qwen/Qwen3.5-4B-MLX-4bit.zip` | ~3 GB Qwen3.5-4B MLX 4-bit pack | `OLD/scripts/package_qwen35_4b_mlx_zip.sh` (or reuse the already-packaged zip in `OLD/build/` if present) |
| `https://vovo.kraftek.cloud/qwen/Qwen3.5-4B-MLX-4bit.zip.sha256` | hex sidecar | same script |
| `https://vovo.kraftek.cloud/imagepack/AnimeImg2Img-SD15.zip` | ~1.5 GB compiled `.mlmodelc` pack (TextEncoder, VAEDecoder, **VAEEncoder**, UnetChunk1+2, vocab.json, merges.txt; SafetyChecker stripped) | `OLD/scripts/package_anime_img2img_mlpackage.sh --chunk-unet --split-einsum-v2` |
| `https://vovo.kraftek.cloud/imagepack/AnimeImg2Img-SD15.zip.sha256` | hex sidecar | same script |

Notes for the server: plain static hosting, HTTPS, big files — byte-range support is
nice-to-have (enables resumable downloads) but not required. Both apps fetch the
`.sha256` **before** the zip and fail fast if missing.

---

## 6. The one hard technical blocker: swift-transformers conflict

**Problem.** `apple/ml-stable-diffusion` 1.1.1 declares an **exact** pin
`swift-transformers == 0.1.8`, while the MLX LLM/VLM stack needs swift-transformers
1.x (1.3.3). SwiftPM allows exactly one version of a package per graph → ImageGenKit
and StoryPromptKit can never live in the same target with stock Apple packages.
This is why `OLD` kept ImageGenKit in a separate debug app (documented in
`OLD/docs/ON_DEVICE_IMG2IMG.md`).

**Resolution (Phase 2).** Vendor our own fork as a sibling checkout
(`~/Projects/ml-stable-diffusion`), mirroring the existing Prism mlx-fork pattern
managed by `setup_mlx_local.sh`:

- **Attempt A (preferred):** bump the fork's pin to swift-transformers 1.x and patch
  the tokenization call sites inside `StableDiffusionPipeline`/resources loading for
  the 1.x API.
- **Attempt B (fallback):** keep transformers 0.1.8 in the fork but **rename the
  module** (e.g. `TransformersCompat`) and rewrite the fork's imports — two
  transformers versions then coexist in one graph without collision.
- Then: `ImageGenKit` depends on the local fork instead of the Apple remote; the
  conflict disappears and all kits (plus StorybookKit) share one graph.

**Acceptance:** all four kit `swift test` suites green; the new host target links
`VovoUI + StorybookKit` (transitively all kits) and builds for the physical device.

---

## 7. Phase plan

### Phase 0 — Fresh skeleton + device pipeline (½ day)
1. Commit the `OLD/` move as the baseline snapshot.
2. Generate the new `Vovozinha.xcodeproj` (decide: XcodeGen `project.yml` like walker,
   or reuse `OLD/scripts/gen_pbx.py`). Host app target only (no harnesses yet);
   team `FTS4YLJNG3`, iOS 18+, increased-memory entitlement, automatic signing.
3. `Scripts/deploy.sh` — inas pattern: `export DEVELOPER_DIR=/Applications/Xcode-beta.app`,
   `xcrun devicectl device info details --device $UDID` pre-check (hard fail if not
   connected), `xcodebuild -destination "platform=iOS,id=$UDID" build`,
   `xcrun devicectl device install app`, `devicectl device process launch`.
   `DESTINATION`/`IPHONE_UDID` env overrides.
4. Port `Packages/VovoUI` verbatim; host shows a placeholder screen. Deploy to the
   iPhone to prove the loop.
   **AC:** app installs + launches on the physical device from the command line.

### Phase 1 — vovo-only model provisioning (1 day)
1. Port `StoryPromptKit` (minus nothing) and `PhotoDescribeKit`; link host to
   StoryPromptKit; recreate the story feature screen (gate + create flow) from
   `OLD/Packages/StoryPromptKit/Sources/StoryPromptKit/StoryPromptFeatureView.swift`.
2. `OnDeviceMLXModelStore`: URLs → vovo.kraftek.cloud only; **delete**
   `files.kraftek.dev` constants + HF fallback page plumbing; keep sha256-sidecar
   verify, install-hash sidecar, update check, import, legacy migration.
3. Same URL surgery in `CoreMLImagePackStore` (still only linked by its own debug
   target until Phase 2; tests keep running via `swift test`).
4. Upload both packs to vovo.kraftek.cloud (§5); exercise both gates on device:
   download → verify → install → generate a real story.
   **AC:** end-to-end story generation on device with only vovo.kraftek.cloud as
   network source; airplane-mode story generation works after install.

### Phase 2 — Conflict resolution + txt2img (2–4 days, spike risk)
1. Vendor + patch the ml-stable-diffusion fork (§6, attempt A → B).
2. Repoint `ImageGenKit/Package.swift`; all kit suites green together.
3. Add **txt2img**: `ImageGenConfig.mode = .textToImage | .imageToImage`;
   capability-aware pack check (txt2img: TextEncoder+UNet(+chunks)+VAEDecoder;
   img2img additionally VAEEncoder); wire through `PipelineCache`; unit tests for
   both modes and capability mapping.
4. Add ImageGenKit (+ transitive kits) to the host target; build for device.
   **AC:** host target compiles with the full kit graph on the physical device;
   both txt2img and img2img exercised via a temporary debug screen.

### Phase 3 — StorybookKit pipeline (3–5 days)
1. New package `StorybookKit`; port/extend from kits:
   - `IllustrationPromptGenerator` (StoryPromptKit): one LLM pass → 10 numbered
     scene prompts; template `illustration.<lang>.md` (placeholders: story text,
     style rules, photo-caption elements); lenient parse (missing lines → error,
     never fabricate); `<think>`-strip reuse.
   - `StoryPage` model + `SeedPipeline` + events (§4.3).
   - `MemorySequencer`: MLX release → `os_proc_available_memory` check → Core ML
     load; strict one-render-at-a-time loop.
2. Consistency (invariant 9): stable per-story base seed (SHA-256-derived, §12.3),
   page seeds, locked style prefix + negative, one locked character-descriptor
   string reused in all 10 illustration prompts, and the cartoonified-reference
   pass (§4.3 step [4]) persisted as `reference.png` before the page loop.
   Spike: tune per-page strength for scene divergence vs cast recognizability
   (§12.4).
3. Mocked-engine unit tests for: ordering, event stream, failure mapping, memory
   hand-off, parse strictness.
   **AC:** pipeline produces a full 10-page book (text + 10 renders) inside unit
   tests with mocks; on device, one full run completes with zero jetsam kills.

### Phase 4 — Unified host UI (3–5 days)
1. Age gate (port from `OLD/Legacy`), Create / Reader / Library / Settings (§4.5).
2. Dual-pack model gate screen; async illustration fill in Reader (page-order
   placeholders → images); save-to-Library (SwiftData + files, §4.4); PDF export;
   share sheet; delete book.
3. All strings in the 3 Markdown tables; parent-friendly copy (no internal
   codenames); accessibility IDs; update/re-add UITests.
   **AC:** full user journey completable on device without any dev tools.

### Phase 5 — Device validation + docs (1–2 days)
1. Full matrix on the iPhone: with photo / without photo × 3 languages; fresh
   install (both packs via vovo) / update path (changed hash on CDN) / remove +
   re-download; memory + timing log per page (tune steps, likely 12–20 at 512²);
   battery sanity.
2. Harness decision: re-create per-feature debug apps only if needed.
3. Fresh docs (`docs/`), root `AGENTS.md` rewrite (paths + invariants + device
   commands), README; `swift test` all packages + `Scripts/test.sh` (XCUITest on
   device, inas pattern).
   **AC:** clean-machine setup from README succeeds; all suites green on device.

---

## 8. Command cheat-sheet

```bash
# Environment
export DEVELOPER_DIR=/Applications/Xcode-beta.app
UDID=00008130-001C78EC18EB8D3A
DEST="platform=iOS,id=$UDID"

# Never use the simulator. Physical only:
xcrun devicectl device info details --device $UDID   # connectivity pre-check

# Build + run
xcodebuild -project Vovozinha.xcodeproj -scheme Vovozinha -destination "$DEST" build
xcrun devicectl device install app --device $UDID <path/to/Vovozinha.app>
xcrun devicectl device process launch --device $UDID <bundle-id>

# Tests
swift test --package-path Packages/StoryPromptKit    # (and the other kits)
Scripts/deploy.sh                                    # build + install + launch
Scripts/test.sh                                      # XCUITest on device
```

---

## 9. Invariants (carried over from `OLD/docs/`, non-negotiable)

1. **Offline product:** all inference on device. Network = model downloads from
   vovo.kraftek.cloud only. No HF/files.kraftek.dev code paths remain.
2. **Never fabricate:** story parse failures are errors surfaced to the user, never
   padded with template text; exactly 10 paragraphs/pages.
3. **Languages:** pt-BR / en-US / es-ES everywhere, via the Markdown string tables.
4. **Storage:** packs in `Application Support/Vovozinha/…` (backup-excluded, hash
   sidecar recorded); user exports under `Documents/Vovozinha/…`.
5. **Memory:** one engine resident at a time; `MLX.Memory.clearCache()` after each
   generation; Core ML pipeline refuses to load under the 900 MB floor.
6. **Kids-safe imagery:** locked negative prompt scaffold from
   `img2img.<lang>.md`; safety checker stays stripped but prompts are locked.
7. **Physical device only.** Simulator is never a build/test target.
8. **Users are parents/caregivers (18+):** age gate required; copy in the user's
   language.
9. **Temporal & element coherence (text + image) — EXTREMELY IMPORTANT:**
   when a photo is provided, the ORIGINAL image is used exactly once to extract
   its elements and "cartoonify" them into a per-story reference (§4.3 step [4]);
   that reference — never the raw photo — is the img2img base for all 10 pages.
   Text side: caption elements are woven into the story and one locked
   character-descriptor string is reused verbatim in every illustration prompt.
   A book whose cast changes appearance between pages is a defect, not a style
   choice.

---

## 10. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| transformers-1.x API drift too big in the SD fork | Medium | Attempt B (renamed 0.1.8 vendored module) is mechanical, not research |
| Per-page render time (25 steps × 11 renders ≈ 15–35 min) | High | Async fill in Reader; tune steps 12–20; reference pass then page 1 (cover) first, then 2→10 (§12.18) |
| Qwen 4B unreliable at emitting 10 clean illustration prompts | Medium | Strict parser (missing line = error, never fabricate) + one automatic retry; validate before rendering starts (§12.26) |
| Jetsam when loading Core ML after MLX | Medium | MemorySequencer + explicit unload + `os_proc_available_memory` guard; measure in Phase 3 |
| Large CDN files / flaky mobile networks | Medium | sidecar-first verify, resume-friendly download controller (already exists), Import fallback |
| CLIP 77-token overflow (style + lock + scene) | High | Unique page scene first; cap the English character lock; see §12.12–12.13 |
| No-photo face drift (invariant 9 photo-only) | High | Same reference-pass architecture without a photo: txt2img one `reference.png`, then img2img pages (§12.17) |
| Pack download dies on background | High | `URLSessionConfiguration.background` (today: `.default`); Wi-Fi confirm (§12.6, §12.22) |
| `PipelineCache.loadFailed` sticky after MLX | Medium | `reset()` + backoff retry; `os_proc_available_memory` lags Metal reclaim (§12.16, §12.24) |
| Thermal throttling on 10–11 back-to-back ANE runs | High | Measure per-page timings in Phase 5; optional cool-down; keep-awake already in §12.1 |

---

## 11. Open questions (ask when the phase reaches them)

1. XcodeGen (`project.yml`, walker-style) vs `gen_pbx.py` for the new project — decide in Phase 0.
2. PDF export: custom `UIGraphicsPDFRenderer` layout vs share-as-images only — decide in Phase 4.
3. Should Library sync/back up books? (Default: no, purely local.)
4. Future SDXL/Animagine XL 4.0 pack (~5–7 GB, per `OLD/docs/ON_DEVICE_IMG2IMG.md`) — out of scope for v1; architecture keeps bucket/model-size seams.

---

## 12. Implementation review remarks (2026-08-31)

Findings from review passes over this plan, verified against `OLD/` kits, Legacy
prompt builders, and upstream sources. Ordered roughly by severity. 0–11 are the
first pass (several already incorporated into §4 / §9); 12–27 are implementation
landmines found on a second pass.

0. **OLD/ independence (hard rule, per Thiago).** Nothing in the new tree references
   `OLD/` — no path deps, no resource references, no script invocations. Every file
   the build needs is created or recreated fresh at the root layout: kits, resources
   (string tables, `story.<lang>.md`, `img2img.<lang>.md`, `illustration.<lang>.md`),
   scripts (`setup_mlx_local.sh`, packagers, `deploy.sh`, `test.sh`), entitlements,
   docs. "Port" in §3 means *recreate using OLD as reference*, never "reference in
   place". Success test: `OLD/` can be deleted and everything still builds.
1. **App suspension during the long render (biggest gap).** 10 pages × 1–3 min each
   = 10–30 min with the screen on. If the user locks the phone or backgrounds the
   app, iOS suspends it and the book dies mid-render. Add: `isIdleTimerDisabled`
   during rendering; per-page PNGs persisted to disk as they complete (already in
   §4.4); **pipeline resume on relaunch** — skip pages whose image file already
   exists so a killed/interrupted run continues instead of restarting. Affects
   Phase 3 (pipeline) + Phase 4 (UI) + §10 risks.
2. **Thermal throttling.** 10–11 back-to-back ANE inferences will heat the device;
   later pages render slower than earlier ones. Now in the §10 table; measure
   per-page timings in Phase 5 and consider a short cool-down if throttling shows.
3. **Seed stability bug in §4.3.** `baseSeed = UInt32(storyID hash)` must NOT use
   Swift's `hashValue`/`Hasher` — it is randomly seeded per process, so a reopened
   book would derive different page seeds. Use a stable hash instead (e.g. first 4
   bytes of SHA-256 of the storyID).
4. **img2img base for all 10 pages — resolved by design, still needs a spike.**
   Update (per Thiago): pages no longer img2img the raw photo directly. The ORIGINAL
   photo is cartoonified ONCE into a per-story reference (§4.3 step [4], invariant 9),
   and that reference is the base for every page — this is the element-coherence
   mechanism. What still needs validation in a Phase 3 spike before locking the
   recipe: per-page strength (likely lower, 0.45–0.55, so scenes can diverge from the
   reference's composition while keeping the cast), and how much scene composition
   may drift before characters stop being recognizable. §10 render-time risk covers
   hiding latency, not this quality trade-off.
5. **MLX release ordering (§4.3) — incorporated.** Step [3] (IllustrationPromptGenerator)
   is also an LLM pass, so MLX must be released only *after* [3] completes.
   §4.3 now states this explicitly (`[---] MLX released here (after [3], never
   before)`); `MemorySequencer` owns that boundary.
6. **First-run download ~4.5 GB.** The gate screen should recommend Wi-Fi / confirm
   before using cellular, and preflight free disk space — zip + extracted pack
   coexist during install, so peak headroom is several GB beyond the final size.
7. **Update-check false positives.** `zip -0` repackaging changes the sha256 even
   for identical content (per `OLD/AGENTS.md`) → any CDN repack looks like an
   "update available". Either stamp packs with an explicit version file, or accept
   the behavior deliberately and document it.
8. **Phase 1 AC depends on a manual CDN upload.** Upload the already-built Qwen zip
   (`OLD/build/Qwen3.5-4B-MLX-4bit.zip` + sidecar, verified present, 2.9 GB) at the
   *start* of Phase 1; the image pack zip is not built yet and only blocks Phase 2.
9. **Environment steps missing from Phase 0/1.** `Scripts/setup_mlx_local.sh`
   (recreated) must run before the first kit build — no `mlx-swift`/`mlx-swift-lm`
   checkouts exist on this machine right now. Also: `xcodebuild
   -downloadComponent MetalToolchain` on the Xcode beta, and mlx-swift-lm pinned
   @ 3.31.4 (patched to path-depend on the local mlx-swift).
10. **Attempt C for §6 (optional third way).** Verified: upstream
    `apple/ml-stable-diffusion` `main` still pins `swift-transformers` exactly
    0.1.8, and the SD Swift package uses it *only* for the CLIP BPE tokenizer
    (vocab.json/merges.txt). So besides A (bump pin) and B (rename module), the
    fork could drop the dependency entirely and vendor a minimal CLIP tokenizer —
    removes the duplicated-transformers problem at the root. Keep A→B order; try C
    only if A/B turn messy. Also verified: the pack already mandates VAEEncoder, so
    txt2img needs no new model files — the §7 Phase 2 capability check is trivial.
11. **Trivia:** §11 item 2 had a stray space in "` UIGraphicsPDFRenderer`" — fixed.

12. **CLIP 77-token budget (coherence vs scene) — Phase 3 spike item.** SD1.5 CLIP
    truncates at 77 tokens. The locked style prefix is already ~20 tokens
    (`anime illustration, soft cel shading, …`). Adding a verbatim character
    descriptor plus a scene prompt will overflow; whichever half sits past token
    77 is silently dropped. Legacy `ScenePromptBuilder` already solved this:
    unique page scene **first** (CLIP weights early tokens), then a **short**
    English identity clause. Cap the lock to ~15–25 tokens (hair, colors, outfit,
    species — not a paragraph). Otherwise every page looks like the same
    establish shot, or faces drift because the lock got truncated. Fold into
    the §12.4 strength spike.

13. **Illustration prompts must be English, even when the story is not.** CLIP is
    English-only. `img2img.<lang>.md` style prefixes are already English in all
    three files (good). `illustration.<lang>.md` must instruct Qwen to emit
    **English visual prompts** (and an English character-descriptor) regardless
    of story language. Story body / title / summary stay in the user's language.
    A pt-BR illustration prompt against this pack will look like a random
    drawing.

14. **Protocol seams don't match §4.3 yet — not "just wire it up".** Today:
    - `StoryFromPromptGenerating.generate(from:)` has no `imageContext`;
      `story.<lang>.md` has no caption placeholder. Step [2] needs both.
    - `ImageGenerating` / `ImageGenInput` / `PipelineCache.generate` /
      `CoreMLImageGenSessioning` all **require** a source `CGImage`. txt2img is
      a real API change (Phase 2), not a config flag.
    - `PhotoCaption` is one unstructured paragraph. Deriving the locked
      character-descriptor is unspecified: deterministic extract vs extra LLM
      pass. Prefer deriving it **inside** the illustration-prompt pass (step
      [3]) as one more labelled line in the same reply — do not add a 4th MLX
      round-trip.

15. **VLM vs LLM factory switch between [1] and [2].** Caption loads via
    `VLMModelFactory` (vision weights kept, ~0.67 GB extra). Story +
    illustration prompts load via `LLMModelFactory` (drops `vision_tower`).
    Current sessions also **load-and-drop per `send()`**. Two failure modes:
    (a) if both factories cache, VLM+LLM coreside → jetsam; (b) three cold
    loads of a ~2.4 GB pack before any image, and the parent waits minutes
    before the Reader even opens. Prefer one container across [1][2][3] —
    keep the VLM loaded for the text passes if memory allows, then explicitly
    unload the factory cache before Core ML. MemorySequencer owns that
    VLM-kept (or VLM→LLM) boundary, not only "after [3]".

16. **`PipelineCache.loadFailed` is a one-way trap.** First SD load under the
    900 MB floor sets `loadFailed = true`; every later `generate` throws until
    `reset()`. After MLX release, `os_proc_available_memory` often still
    reports low because Metal buffers return slowly. MemorySequencer must
    call `PipelineCache.reset()`, retry the load with a short backoff, and
    never leave the sticky flag set across stories. Port this as part of
    Phase 2, not as a later bugfix.

17. **No-photo path has no image-side coherence mechanism.** Invariant 9 only
    specifies the photo path. txt2img with a reused prompt lock still changes
    faces on SD1.5 — a book whose cast morphs is still a defect. Use the
    **same** two-stage recipe with no photo: one txt2img character/element
    reference (step [4] equivalent, `seed: baseSeed`) persisted as
    `reference.png`, then img2img every page from that. Unifies both paths
    and gives the no-photo book a cast. Validate in the Phase 3 spike
    alongside §12.4.

18. **11 renders, not 10; cover-first vs page-order conflict.** Photo path =
    1 reference + 10 pages (11 if §12.17 is adopted for no-photo too). §10
    still estimates `25 steps × 10 pages` and says "cover page first so the
    reader is complete early", which contradicts §4.3's strict 1→10 order.
    Pick one and write it down: render **page 1 first** after the reference
    (it is the cover; the Reader looks complete sooner), then 2→10. Progress
    denominator includes the reference pass. Update the §10 time estimate to
    11× (or 10× for no-photo if [4] is skipped).

19. **Reader-after-[2] vs MLX still needed for [3].** §4.5 jumps to Reader as
    soon as page texts are ready, but [3] is still an LLM pass. Navigating
    after [2] either (a) keeps MLX resident while the parent reads — so SD
    cannot start, and a background kills [3] — or (b) needs texts persisted
    first. Stay on a "preparing pictures" phase through [3], persist
    draft + 10 prompts + character-descriptor, **then** release MLX and open
    Reader with text. Don't start SD until that hand-off completes.

20. **Resume / persist model is incomplete in §4.4.** Pipeline resume (§12.1)
    needs more than `page-N.png` + `reference.png`. Add: `pipelinePhase`,
    `baseSeed`, `characterDescriptor`, original photo bytes (until [4]
    succeeds), and the 10 `illustrationPrompt`s. Store image locations as
    **relative** names (`page-N.png`), never absolute `file://` URLs —
    the app-container UUID changes across reinstall/update. Persist each PNG
    **then drop** the `CGImage` before the next page (`ImageGenResult.cgImage`
    is also not really `Sendable`). `PipelineEvent.illustrationReady` should
    carry a file URL, not a bitmap.

21. **Cartoonify recipe is underspecified (quality + safety).** Who writes
    `referencePrompt`? Fixed style prefix + caption, or another LLM pass?
    Strength 0.6 against a *real photo* often leaves photoreal residue —
    that fights invariant 6 (kids-safe, no real faces) **and** can leak a
    child's likeness. Reference pass likely needs **higher** strength
    (0.7–0.85) than page passes (0.45–0.55). Also: multi-person / pet-only
    photos make "the" character-descriptor singular; define whether the lock
    describes the group or the most prominent subject. And EXIF orientation:
    `ImageGenInput.makeCGImage()` uses `UIImage.cgImage`, which **ignores**
    `imageOrientation` — iPhone camera HEICs (typical `.right` / 6) will
    cartoonify sideways. Normalize orientation at decode (PhotosPicker and
    img2img). Fold all of this into the Phase 3 spike.

22. **Foreground-only pack downloads.** Both zip controllers use
    `URLSessionConfiguration.default` (6 h resource timeout, but the task is
    suspended with the app). A ~3 GB Qwen zip dies if the parent backgrounds
    or locks the phone — same class of bug as §12.1, for Phase 1. Use a
    background `URLSession` (or at least `beginBackgroundTask` plus copy that
    says "keep the app open"). Today's stores also set
    `allowsConstrainedNetworkAccess = true`; that bypasses the Wi-Fi confirm
    in §12.6. Sequential downloads, not parallel (disk + network).

23. **Cancellation / single-flight.** No abort path. The parent can tap
    Create twice, leave Create, delete the in-progress book, or switch
    language mid-run. `SeedPipeline` must be a single-flight `Task`, call
    `Task.checkCancellation()` between steps/pages, unload MLX and the SD
    pipeline on cancel, and never leave a SwiftData row without a resumable
    `pipelinePhase`. A second Create while one is running is an error, not a
    second pipeline.

24. **Memory after MLX: retry, don't one-shot the 900 MB gate.**
    `os_proc_available_memory` is not instant after `MLX.Memory.clearCache()`.
    A brief sleep + retry (and log free bytes at each MemorySequencer
    boundary in Phase 5) or the first on-device run fails even when the
    sequence is correct. Pairs with §12.16.

25. **Path-dep naming nit in §3.1.** Kits path-depend `../../../mlx-swift`
    and `../../../mlx-swift-lm` — correct once packages live at `Packages/`
    again (that resolves to `~/Projects/mlx-swift`, sibling of this repo).
    §3.1 currently says `../../mlx-swift` + `../../mlx-lm`: wrong depth and
    wrong checkout name. `Scripts/setup_mlx_local.sh` (recreated) clones
    those two siblings; run it before the first kit build (§12.9).

26. **Parse wording: "lenient" vs never-fabricate.** §4.3 says "numbered-line
    parse; lenient"; Phase 3 says missing lines → error, never fabricate.
    That is **strict**, not lenient. One automatic retry (already in §10),
    then surface the error. Do not accept 9 prompts or pad a 10th. Same
    contract as the story parser.

27. **Harvest `CharacterProfile.artIdentityLock` from Legacy, don't port the
    rest.** Legacy already maps PT/ES appearance phrases onto English visual
    tags and puts scene tokens first (`ScenePromptBuilder`). Steal that for
    the locked descriptor. Do **not** port `StoryArtMemory` / previous-page
    img2img unless the Phase 3 spike shows the cartoon-reference isn't
    enough for cast recognizability. Previous-page chaining is the fallback
    recipe, not the v1 design.
