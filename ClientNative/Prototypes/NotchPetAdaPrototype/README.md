# AdaEngine Notch Pet Prototype

Standalone macOS prototype of the notch character rendered by AdaEngine.
The notch window itself uses AdaEngine's native `WindowSettings`; the character,
textures, transforms, animation state, pointer tracking, and drawing use
AdaEngine ECS and the Metal-backed 2D renderer.

This app is intentionally separate from both Sloppy's production overlay and
the SpriteKit validation prototype.

## Run

```bash
./script/build_and_run.sh --verify
```

Use the sparkle icon in the menu bar to show, hide, or quit the prototype.
