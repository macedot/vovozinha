# Story generation prompts (Markdown)

User-edited **LLM instructions** for the on-device **Bonsai MLX** path. These are **not** static story bodies.

## Files

| File | Language |
|------|----------|
| `litert.en-US.md` | English (US) |
| `litert.pt-BR.md` | Português (Brasil) |
| `litert.es-ES.md` | Español (España) |

(Filenames keep the historical `litert.*` prefix; content is engine-agnostic story instructions.)

## Placeholders

Parent story description replaces:

| Token | Language |
|-------|----------|
| `[INSERT STORY DESCRIPTION HERE]` | en-US |
| `[INSERIR A DESCRIÇÃO DA HISTÓRIA AQUI]` | pt-BR |
| `[INSERTAR LA DESCRIPCIÓN DE LA HISTORIA AQUÍ]` | es-ES |

Also: `{{seed}}`, `{{idea}}`, `{{description}}`.

`StoryPromptTemplate` / `MLXBonsaiStoryGenerator` perform substitution. **Never leave INSERT tokens unreplaced.**

## Product rule

There is **no** offline / template story generator. Without a working on-device model, generation **fails**.
