# Immersive Siri Shell Design

## Goal

Bring the Apple Intelligence Siri-like visual language into the full Sloppy Apple client shell: a black-to-transparent atmospheric background, one translucent blurred shell window, and a soft edge glow around the application surface.

## Scope

The first implementation targets `Apps/Client` only. The effect applies to the connected app shell that contains the sidebar and chat. Splash, setup, and settings keep their existing structure, but still sit on the shared atmospheric background.

## Visual Direction

Use the immersive direction selected in brainstorming:

- Strong black veil at the top that fades toward transparent lower content.
- A full-shell blurred translucent panel instead of independent opaque sidebar/chat backgrounds.
- Subtle white borders and inner highlights to keep the glass readable.
- A soft cyan/pink/violet edge glow inspired by the active Siri edge-light motif.
- A floating composer capsule that reads as glass over the shell, not as an opaque toolbar.

## Architecture

Keep the effect at the shell boundary. `AppAtmosphericBackground` owns the global black-to-transparent ambience. `MainView` wraps the sidebar and chat in a new `SloppyGlassShell` container. Existing feature screens continue to render their content normally inside the shell.

`SloppyEdgeGlowMaterial` remains the shader source for edge glow. The new shell container composes that material with AdaUI glass effects and simple shape layers.

## Testing

Add source-level rendering tests in the client test suite to assert that `MainView` uses the shell container and that the shell applies glass plus the edge glow shader. Then build the client package to verify AdaEngine/AdaUI API compatibility.
