# AdaEngine HarfBuzz Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add HarfBuzz shaping to AdaEngine text layout while preserving the existing MTSDF atlas renderer.

**Architecture:** HarfBuzz is added as a vendored SwiftPM C/C++ target and accessed through a narrow bridge. `AdaText` shapes attributed text runs into glyph ids and positions, then uses the existing atlas glyph geometry and text shader to render.

**Tech Stack:** Swift 6.2, SwiftPM, HarfBuzz C/C++, FreeType/MSDF atlas generator, Swift Testing.

## Global Constraints

- Use a vendored HarfBuzz target, not system HarfBuzz.
- Keep MSDF/MTSDF atlas generation and shader behavior unchanged.
- Keep the current scalar text path as fallback when shaping fails or glyphs are missing.
- Start with single-font run shaping; defer full paragraph bidi and multi-font shaping.
- Write tests before production changes.

---

## File Structure

- `Vendor/AdaEngine/Package.swift`: add HarfBuzz target and bridge target dependencies.
- `Vendor/AdaEngine/Sources/harfbuzz/`: vendored HarfBuzz source and headers.
- `Vendor/AdaEngine/Sources/AdaTextShaper/include/ada_text_shaper.h`: narrow C API consumed by Swift.
- `Vendor/AdaEngine/Sources/AdaTextShaper/AdaTextShaper.cpp`: HarfBuzz bridge implementation.
- `Vendor/AdaEngine/Sources/AtlasFontGenerator/include/atlas_font_gen.h`: expose glyph lookup by glyph index.
- `Vendor/AdaEngine/Sources/AtlasFontGenerator/atlas_font_gen.cpp`: implement glyph lookup by glyph index for live and cached font data.
- `Vendor/AdaEngine/Sources/AdaText/Text/Font/FontHandle.swift`: add `getGlyph(forGlyphIndex:)`.
- `Vendor/AdaEngine/Sources/AdaText/Text/TextShaper.swift`: Swift facade for shaped glyph records.
- `Vendor/AdaEngine/Sources/AdaText/Text/TextLayoutManager.swift`: use shaped glyph records where safe.
- `Vendor/AdaEngine/Tests/AdaTextTests/HarfBuzzShaperTests.swift`: bridge and shaping tests.
- `Vendor/AdaEngine/Tests/AdaTextTests/TextLayoutShapingTests.swift`: layout regression tests.

---

### Task 1: Expose Atlas Glyph Lookup By Glyph Index

**Files:**
- Modify: `Vendor/AdaEngine/Sources/AtlasFontGenerator/include/atlas_font_gen.h`
- Modify: `Vendor/AdaEngine/Sources/AtlasFontGenerator/atlas_font_gen.cpp`
- Modify: `Vendor/AdaEngine/Sources/AdaText/Text/Font/FontHandle.swift`
- Test: `Vendor/AdaEngine/Tests/AdaTextTests/HarfBuzzShaperTests.swift`

**Interfaces:**
- Produces: `font_handle_get_glyph_index(struct font_handle_s* fontData, int glyphIndex) -> font_glyph_s*`
- Produces: `FontHandle.getGlyph(forGlyphIndex glyphIndex: Int32) -> FontHandle.Glyph?`

- [ ] **Step 1: Write the failing test**

```swift
import AdaText
import Testing

@Suite("HarfBuzz shaping support")
struct HarfBuzzShaperTests {
    @Test("FontHandle can resolve glyphs by glyph index")
    func fontHandleResolvesGlyphIndex() {
        let font = FontResource.system(weight: .regular, emFontScale: 52)
        guard let scalarGlyph = font.handle.getGlyph(for: UnicodeScalar("A").value) else {
            Issue.record("Expected system font to contain A")
            return
        }

        var l: Double = 0
        var b: Double = 0
        var r: Double = 0
        var t: Double = 0
        scalarGlyph.getQuadAtlasBounds(&l, &b, &r, &t)

        #expect(font.handle.getGlyph(forGlyphIndex: 0) != nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --package-path Vendor/AdaEngine --filter HarfBuzzShaperTests
```

Expected: FAIL because `getGlyph(forGlyphIndex:)` does not exist.

- [ ] **Step 3: Add the C API declaration**

Add to `atlas_font_gen.h` near `font_handle_get_glyph_unicode`:

```c
struct font_glyph_s* font_handle_get_glyph_index(struct font_handle_s* fontData, int glyphIndex);
```

- [ ] **Step 4: Implement the C API**

Add a `glyphsByIndex` map to `cached_font_data_s`, populate it where cached glyphs are loaded, and add:

```cpp
font_glyph_s* font_handle_get_glyph_index(font_handle_s* fontData, int glyphIndex) {
    if (!fontData) {
        return nullptr;
    }

    if (fontData->cached_data) {
        auto glyph = fontData->cached_data->glyphsByIndex.find(glyphIndex);
        if (glyph == fontData->cached_data->glyphsByIndex.end()) {
            return nullptr;
        }

        font_glyph_s* result = new font_glyph_s();
        result->glyph = nullptr;
        result->cached_glyph = &fontData->cached_data->glyphs[glyph->second];
        return result;
    }

    if (!fontData->font_data) {
        return nullptr;
    }

    const msdf_atlas::GlyphGeometry* glyph = fontData->font_data->fontGeometry.getGlyph(
        msdfgen::GlyphIndex(glyphIndex)
    );
    if (!glyph) {
        return nullptr;
    }

    font_glyph_s* result = new font_glyph_s();
    result->glyph = glyph;
    result->cached_glyph = nullptr;
    return result;
}
```

- [ ] **Step 5: Add Swift wrapper**

Add to `FontHandle`:

```swift
func getGlyph(forGlyphIndex glyphIndex: Int32) -> Glyph? {
    guard let glyph = unsafe font_handle_get_glyph_index(self.fontData, glyphIndex) else {
        return nil
    }

    return unsafe Glyph(ref: glyph)
}
```

- [ ] **Step 6: Run test to verify it passes**

Run:

```bash
swift test --package-path Vendor/AdaEngine --filter HarfBuzzShaperTests
```

Expected: PASS.

---

### Task 2: Add Vendored HarfBuzz Target And C Bridge

**Files:**
- Modify: `Vendor/AdaEngine/Package.swift`
- Create: `Vendor/AdaEngine/Sources/harfbuzz/`
- Create: `Vendor/AdaEngine/Sources/AdaTextShaper/include/ada_text_shaper.h`
- Create: `Vendor/AdaEngine/Sources/AdaTextShaper/AdaTextShaper.cpp`
- Test: `Vendor/AdaEngine/Tests/AdaTextTests/HarfBuzzShaperTests.swift`

**Interfaces:**
- Produces: `ada_text_shape_utf8(...) -> ada_shaped_text_t*`
- Produces: `ada_shaped_text_destroy(...)`
- Produces shaped records with `glyphIndex`, `cluster`, `xAdvance`, `yAdvance`, `xOffset`, `yOffset`.

- [ ] **Step 1: Vendor HarfBuzz sources**

Copy HarfBuzz source into `Vendor/AdaEngine/Sources/harfbuzz` from the approved upstream release. Keep license files intact.

- [ ] **Step 2: Add SwiftPM targets**

Add a `HarfBuzz` target and an `AdaTextShaper` target. `AdaTextShaper` depends on `HarfBuzz`.

- [ ] **Step 3: Write failing bridge smoke test**

Extend `HarfBuzzShaperTests`:

```swift
@Test("HarfBuzz bridge shapes UTF-8 text")
func harfbuzzBridgeShapesText() {
    let font = FontResource.system(weight: .regular, emFontScale: 52)
    let result = TextShaper.shape("Hello", font: font)

    #expect(!result.glyphs.isEmpty)
    #expect(result.glyphs.allSatisfy { $0.glyphIndex >= 0 })
}
```

Expected: FAIL because `TextShaper` does not exist.

- [ ] **Step 4: Implement bridge header**

`ada_text_shaper.h` defines C structs:

```c
typedef struct ada_shaped_glyph_s {
    uint32_t glyphIndex;
    uint32_t cluster;
    double xAdvance;
    double yAdvance;
    double xOffset;
    double yOffset;
} ada_shaped_glyph_t;

typedef struct ada_shaped_text_s {
    ada_shaped_glyph_t *glyphs;
    int glyphCount;
} ada_shaped_text_t;
```

- [ ] **Step 5: Implement bridge**

`AdaTextShaper.cpp` loads a HarfBuzz face/font from font bytes or file path, adds UTF-8 text to an `hb_buffer_t`, calls `hb_buffer_guess_segment_properties`, then `hb_shape`.

- [ ] **Step 6: Add Swift facade**

Create `TextShaper.swift` with:

```swift
struct ShapedGlyph: Equatable {
    let glyphIndex: Int32
    let cluster: Int
    let xAdvance: Double
    let yAdvance: Double
    let xOffset: Double
    let yOffset: Double
}

enum TextShaper {
    static func shape(_ text: String, font: FontResource) -> [ShapedGlyph] {
        // Calls AdaTextShaper; returns [] on failure.
    }
}
```

- [ ] **Step 7: Run bridge test**

Run:

```bash
swift test --package-path Vendor/AdaEngine --filter HarfBuzzShaperTests
```

Expected: PASS.

---

### Task 3: Integrate Shaped Glyphs Into Text Layout

**Files:**
- Modify: `Vendor/AdaEngine/Sources/AdaText/Text/TextLayoutManager.swift`
- Test: `Vendor/AdaEngine/Tests/AdaTextTests/TextLayoutShapingTests.swift`

**Interfaces:**
- Consumes: `TextShaper.shape(_:font:) -> [ShapedGlyph]`
- Consumes: `FontHandle.getGlyph(forGlyphIndex:)`

- [ ] **Step 1: Write failing layout test**

```swift
import AdaText
import Testing

@Suite("Text layout shaping")
struct TextLayoutShapingTests {
    @Test("Ligature shaping reduces fi glyph count when font supports it")
    func ligatureShapingReducesGlyphCount() {
        let text = AttributedText("fi")
        let manager = TextLayoutManager()
        manager.setTextContainer(TextContainer(text: text))
        manager.invalidateLayout()

        let glyphs = manager.glyphsForTesting()
        #expect(glyphs.count <= 2)
    }
}
```

Expected: FAIL because there is no shaped layout path and no testing accessor.

- [ ] **Step 2: Extract glyph append helper**

Move the repeated atlas coordinate and quad-position code into a private helper in `TextLayoutManager`.

- [ ] **Step 3: Add shaped run path**

For contiguous text with the same `TextAttribute.font`, call `TextShaper.shape`. For each shaped glyph, resolve by glyph index and apply HarfBuzz advance/offset. If the shaped result is empty or any glyph lookup fails, use the existing scalar loop.

- [ ] **Step 4: Keep wrapping fallback conservative**

Use shaped path for no-wrap and character-wrap flows first. Keep word-wrap width calculation on the scalar path until shaped measurement is added.

- [ ] **Step 5: Run layout tests**

Run:

```bash
swift test --package-path Vendor/AdaEngine --filter TextLayoutShapingTests
```

Expected: PASS.

---

### Task 4: Regression Verification

**Files:**
- No new files required.

- [ ] **Step 1: Run AdaText tests**

```bash
swift test --package-path Vendor/AdaEngine --filter AdaTextTests
```

Expected: PASS.

- [ ] **Step 2: Run text example build**

```bash
swift build --package-path Vendor/AdaEngine --product Text2dExample
```

Expected: PASS.

- [ ] **Step 3: Run full AdaEngine build**

```bash
swift build --package-path Vendor/AdaEngine
```

Expected: PASS.
