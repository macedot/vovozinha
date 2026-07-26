# UI strings (Markdown)

Static UI copy for **pt-BR / en-US / es-ES**.

## Format

```markdown
# Title (ignored)

## keyName
Visible string. Optional {{placeholders}}.
```

- One file per language: `en-US.md`, `pt-BR.md`, `es-ES.md`
- Keys are `## section` headers (match `VovoL10n.Key` raw values or helper keys)
- Placeholders: `{{min}}`, `{{max}}`, `{{current}}`, `{{index}}`, …

## Edit workflow

1. Change the `.md` file for the language you care about.
2. Rebuild the app / package (files are copied into the bundle via SPM resources).

Loaded by `VovoL10n` → `MarkdownTextCatalog`.
