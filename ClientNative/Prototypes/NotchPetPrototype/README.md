# Notch Pet Prototype

Standalone macOS visual prototype for a small animated character living under
the display notch. It intentionally does not depend on or replace Sloppy's
existing desktop overlay.

The character is rendered procedurally with SpriteKit. It follows the pointer
with its eyes, breathes and floats while idle, blinks, periodically thinks, and
reacts when clicked.

## Run

```bash
./script/build_and_run.sh --verify
```

Use the face icon in the menu bar to show or hide the pet, force the thinking
animation, trigger a reaction, or quit the prototype.
