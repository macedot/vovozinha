# Prompt templates (bundled)

Plain-text templates loaded at runtime via `PromptCatalog`.

## Placeholders

Use `{{name}}` in templates. Substituted by `PromptCatalog.render`.

## Layout

| Path | Used by |
|------|---------|
| `story/system_instructions.txt` | Foundation Models system prompt |
| `story/user_prompt.txt` | Foundation Models user prompt |
| `story/scene_list.txt` | Scene order list injected into system prompt |
| `story/paragraph_example.*.txt` | Density examples / tests |
| `art/negative.txt` | Image negative prompt |
| `art/section.*.txt` | Per-beat image section direction |
| `art/page.establish.txt` / `page.continue.txt` | Positive image prompts |
| `art/refine.txt` | Optional diffusion refine pass |
| `art/style.*.txt` | Art style fragments |

Edit files and rebuild the app (they are copied into the bundle).
