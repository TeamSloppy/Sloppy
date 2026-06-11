import { useEffect, useRef, useState } from "react";

import { HOVER_SOUND_PREFERENCE_EVENT, playHoverSound, resolveHoverSoundTarget } from "./hoverSound";

export function useHoverSoundEffect(enabled: boolean) {
  const [sessionEnabled, setSessionEnabled] = useState(enabled);
  const lastTargetRef = useRef<unknown | null>(null);
  const lastPlayedAtRef = useRef(0);

  useEffect(() => {
    setSessionEnabled(enabled);
  }, [enabled]);

  useEffect(() => {
    if (typeof window === "undefined") {
      return;
    }

    function handlePreferenceChanged(event: Event) {
      const nextEnabled = Boolean((event as CustomEvent<{ enabled?: boolean }>).detail?.enabled);
      setSessionEnabled(nextEnabled);
    }

    window.addEventListener(HOVER_SOUND_PREFERENCE_EVENT, handlePreferenceChanged);
    return () => window.removeEventListener(HOVER_SOUND_PREFERENCE_EVENT, handlePreferenceChanged);
  }, []);

  useEffect(() => {
    if (!sessionEnabled || typeof document === "undefined") {
      return;
    }

    function handlePointerOver(event: PointerEvent) {
      const hoverTarget = resolveHoverSoundTarget(event.target);
      if (!hoverTarget || hoverTarget === lastTargetRef.current) {
        return;
      }
      lastTargetRef.current = hoverTarget;
      playHoverSound({ lastPlayedAtRef });
    }

    function handlePointerOut(event: PointerEvent) {
      const currentTarget = lastTargetRef.current as Node | null;
      const nextTarget = event.relatedTarget;
      if (currentTarget && (!nextTarget || !currentTarget.contains(nextTarget as Node))) {
        lastTargetRef.current = null;
      }
    }

    document.addEventListener("pointerover", handlePointerOver, true);
    document.addEventListener("pointerout", handlePointerOut, true);

    return () => {
      document.removeEventListener("pointerover", handlePointerOver, true);
      document.removeEventListener("pointerout", handlePointerOut, true);
    };
  }, [sessionEnabled]);
}
