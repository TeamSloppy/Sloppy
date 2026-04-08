import React, { useMemo } from "react";
import type { SpritePartMeta } from "./spriteManifest";

interface SpriteLayerProps {
  src: string;
  meta: SpritePartMeta | null;
  className?: string;
}

export function SpriteLayer({ src, meta, className = "" }: SpriteLayerProps) {
  const isAnimated = meta != null && meta.frames > 1 && meta.fps > 0;

  const style = useMemo(() => {
    if (!isAnimated || !meta) return undefined;
    const duration = meta.frames / meta.fps;
    return {
      width: meta.width,
      height: meta.height,
      backgroundImage: `url(${src})`,
      backgroundRepeat: "no-repeat" as const,
      backgroundSize: `${meta.width * meta.frames}px ${meta.height}px`,
      animationName: "sprite-sheet-play",
      animationTimingFunction: `steps(${meta.frames})`,
      animationDuration: `${duration}s`,
      animationIterationCount: "infinite" as const,
    };
  }, [src, meta, isAnimated]);

  if (isAnimated) {
    return <div className={`sprite-layer sprite-layer--sheet ${className}`.trim()} style={style} />;
  }

  return (
    <img
      className={`sprite-layer ${className}`.trim()}
      src={src}
      alt=""
      draggable={false}
    />
  );
}
