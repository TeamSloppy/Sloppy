# AdaEngine HarfBuzz Integration Design

## Goal

Add HarfBuzz text shaping to AdaEngine's `AdaText` pipeline while keeping the existing MSDF/MTSDF atlas rendering path.

## Scope

The first implementation slice adds HarfBuzz as a vendored dependency and routes text layout through a shaping layer for single-font runs. Existing scalar-based glyph resolution remains as the fallback path for unsupported cases, missing glyphs, and platform-specific fallback font handling.

## Architecture

AdaEngine already uses FreeType, msdfgen, and msdf-atlas-gen to load `.ttf`/`.otf` fonts and generate MTSDF atlases. HarfBuzz should sit before atlas lookup:

```text
AttributedText run
  -> HarfBuzz shape
  -> glyph ids + advances + offsets + clusters
  -> FontHandle glyph lookup by glyph index
  -> existing MTSDF glyph quads and text shader
```

The renderer should not change atlas generation or shader logic. HarfBuzz changes how glyphs and positions are selected.

## Dependency Strategy

Use a vendored HarfBuzz SwiftPM target inside `Vendor/AdaEngine`, matching the existing FreeType/MSDF strategy. Avoid system package dependencies because AdaEngine needs reproducible builds across local development, CI, and browser/WASM export.

The target should expose only a small C-compatible bridge to Swift. Swift code in `AdaText` should not depend directly on broad HarfBuzz C APIs.

## Components

- `HarfBuzz` target: vendored HarfBuzz C/C++ sources and public headers.
- `AdaTextShaper` bridge: a narrow C-compatible wrapper that accepts font bytes or a font path plus UTF-8 text, then returns shaped glyph records.
- `TextShaper` Swift facade: converts `AttributedText` runs into shaped glyph records.
- `FontHandle` extension: retrieves glyph atlas data by glyph index in addition to Unicode scalar.
- `TextLayoutManager` integration: uses shaped glyph records for layout when the run can be shaped with one font, otherwise falls back to current scalar layout.

## Behavior

For simple Latin/Cyrillic text, visual output should remain equivalent to the current implementation. For OpenType shaping cases, such as standard ligatures and complex scripts, HarfBuzz should provide the glyph ids and positions.

The initial implementation does not need full bidirectional paragraph layout, custom OpenType feature APIs, or multi-font shaping inside one HarfBuzz buffer. Those can be layered on later.

## Error Handling

If HarfBuzz cannot load a font, shape text, or return a glyph that exists in the atlas, `AdaText` falls back to the existing Unicode scalar path. Runtime text rendering must not crash because of shaping failure.

## Testing

Tests should cover:

- A HarfBuzz bridge smoke test shapes simple text and returns glyph records.
- A ligature-capable font shapes `"fi"` into fewer glyphs than the scalar path when standard ligatures are enabled.
- Existing text layout remains stable for simple Latin/Cyrillic strings.
- Missing glyph or shaping failure falls back to current glyph resolution.

## Non-Goals

- Replacing MSDF/MTSDF atlas generation.
- Replacing the text shader.
- Implementing full paragraph bidi segmentation in the first slice.
- Depending on system HarfBuzz installations.
