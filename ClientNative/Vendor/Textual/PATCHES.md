# Local Textual patches

This directory vendors Textual 0.5.0 (`01b51875a5406eefc95f52a058cb059e7bc94dc4`).
It keeps the upstream renderer and styles while applying three layout-stability fixes:

- `TextBuilder.sizeChanged` does not publish a new `Text` when attachment sizes are unchanged.
- `TextSelectionBackground` does not install its AppKit geometry overlay unless Textual selection is enabled.
- `AppKitTextSelectionView` does not write duplicate selection rectangles into SwiftUI state.

The upstream examples, snapshots, and tests are intentionally omitted from the vendored runtime copy.
