import { useEffect, useRef, useState } from "react";

import { HOVER_SOUND_PREFERENCE_EVENT, HOVER_SOUND_STORAGE_KEY, loadHoverSoundPreference, playHoverSound, resolveHoverSoundTarget } from "./hoverSound";

export function useHoverSoundEffect() {
  const [sessionEnabled, setSessionEnabled] = useState(loadHoverSoundPreference);
  const lastTargetRef = useRef<unknown | null>(null);
  const lastPlayedAtRef = useRef(0);

  useEffect(() => {
    if (typeof window === "undefined") {
      return;
    }

    function handlePreferenceChanged(event: Event) {
      const nextEnabled = Boolean((event as CustomEvent<{ enabled?: boolean }>).detail?.enabled);
      setSessionEnabled(nextEnabled);
    }

    function handleStorageChanged(event: StorageEvent) {
      if (event.key === HOVER_SOUND_STORAGE_KEY) {
        setSessionEnabled(loadHoverSoundPreference());
      }
    }

    window.addEventListener(HOVER_SOUND_PREFERENCE_EVENT, handlePreferenceChanged);
    window.addEventListener("storage", handleStorageChanged);
    return () => {
      window.removeEventListener(HOVER_SOUND_PREFERENCE_EVENT, handlePreferenceChanged);
      window.removeEventListener("storage", handleStorageChanged);
    };
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
