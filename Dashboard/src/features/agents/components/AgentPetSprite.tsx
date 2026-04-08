import React, { useEffect, useState } from "react";
import { SpriteLayer } from "./SpriteLayer";
import {
  type SpriteManifest,
  loadManifest,
  getManifestSync,
  hasPngSprite,
  spriteSrc,
  spritePartMeta,
} from "./spriteManifest";

type Pixel = [number, number, number?, number?];

type SpritePart = {
  pixels: Pixel[];
  fill: string;
  stroke?: string;
};

const HEADS: Record<string, SpritePart> = {
  "head-bubble": { fill: "#9ff3ff", pixels: [[4, 0, 4, 1], [3, 1, 6, 2], [2, 3, 8, 3], [3, 6, 6, 1], [4, 7, 4, 1], [2, 4, 1, 1], [9, 4, 1, 1], [4, 4, 1, 1], [7, 4, 1, 1]] },
  "head-cube": { fill: "#c3ffd0", pixels: [[3, 1, 6, 1], [2, 2, 8, 5], [3, 7, 6, 1], [4, 4, 1, 1], [7, 4, 1, 1]] },
  "head-shell": { fill: "#f9d69f", pixels: [[4, 0, 4, 1], [3, 1, 6, 1], [2, 2, 8, 1], [1, 3, 10, 3], [2, 6, 8, 1], [3, 7, 6, 1], [4, 4, 1, 1], [7, 4, 1, 1]] },
  "head-fork": { fill: "#f3a6ff", pixels: [[3, 0, 1, 2], [8, 0, 1, 2], [4, 1, 4, 1], [2, 2, 8, 5], [4, 4, 1, 1], [7, 4, 1, 1]] },
  "head-visor": { fill: "#9fb4ff", pixels: [[3, 1, 6, 1], [2, 2, 8, 4], [3, 6, 6, 2], [3, 3, 6, 2], [4, 7, 1, 1], [7, 7, 1, 1]] },
  "head-probe": { fill: "#ffb27a", pixels: [[5, 0, 2, 1], [6, 1, 1, 1], [3, 2, 6, 5], [4, 4, 1, 1], [7, 4, 1, 1], [2, 5, 1, 1], [9, 5, 1, 1]] },
  "head-oracle": { fill: "#9df0ce", pixels: [[5, 0, 2, 1], [4, 1, 4, 1], [3, 2, 6, 1], [2, 3, 8, 4], [3, 7, 6, 1], [4, 4, 1, 1], [7, 4, 1, 1], [5, 6, 2, 1]] },
  "head-crown": { fill: "#ffe266", pixels: [[2, 1, 2, 1], [5, 0, 2, 1], [8, 1, 2, 1], [3, 2, 6, 1], [2, 3, 8, 4], [4, 4, 1, 1], [7, 4, 1, 1], [3, 7, 6, 1]] }
};

const BODIES: Record<string, SpritePart> = {
  "body-core": { fill: "#78d7ff", pixels: [[4, 8, 4, 1], [3, 9, 6, 1], [2, 10, 8, 4], [3, 14, 6, 1]] },
  "body-puff": { fill: "#f8b6d2", pixels: [[3, 8, 6, 1], [2, 9, 8, 1], [1, 10, 10, 3], [2, 13, 8, 2], [4, 11, 1, 1], [7, 11, 1, 1]] },
  "body-brick": { fill: "#cbb7ff", pixels: [[3, 8, 6, 1], [2, 9, 8, 5], [3, 14, 6, 1], [4, 10, 4, 1], [4, 12, 4, 1]] },
  "body-terminal": { fill: "#90ffac", pixels: [[2, 8, 8, 1], [1, 9, 10, 5], [2, 14, 8, 1], [3, 10, 6, 2], [3, 12, 2, 1], [7, 12, 2, 1]] },
  "body-satchel": { fill: "#ffcf8d", pixels: [[3, 8, 6, 1], [2, 9, 8, 5], [3, 14, 6, 1], [8, 11, 2, 2], [1, 10, 1, 3]] },
  "body-relay": { fill: "#ff9c9c", pixels: [[3, 8, 6, 1], [2, 9, 8, 2], [1, 11, 10, 2], [2, 13, 8, 2], [4, 10, 1, 1], [7, 10, 1, 1]] },
  "body-reactor": { fill: "#82f3d9", pixels: [[4, 8, 4, 1], [3, 9, 6, 1], [2, 10, 8, 5], [4, 11, 4, 2], [5, 15, 2, 1]] },
  "body-throne": { fill: "#ffdd78", pixels: [[2, 8, 8, 1], [1, 9, 10, 6], [3, 10, 6, 1], [4, 11, 4, 2], [3, 15, 6, 1]] }
};

const LEGS: Record<string, SpritePart> = {
  "legs-stub": { fill: "#8fc2ff", pixels: [[3, 16, 2, 3], [7, 16, 2, 3]] },
  "legs-bouncer": { fill: "#c9ff9b", pixels: [[3, 16, 2, 2], [2, 18, 3, 1], [7, 16, 2, 2], [7, 18, 3, 1]] },
  "legs-track": { fill: "#ffc9a8", pixels: [[2, 16, 8, 1], [1, 17, 10, 2]] },
  "legs-sprinter": { fill: "#ffb1f1", pixels: [[3, 16, 1, 3], [4, 18, 2, 1], [8, 16, 1, 3], [6, 18, 2, 1]] },
  "legs-spider": { fill: "#99f0ff", pixels: [[2, 16, 2, 1], [1, 17, 2, 1], [3, 18, 2, 1], [8, 16, 2, 1], [9, 17, 2, 1], [7, 18, 2, 1]] },
  "legs-piston": { fill: "#e4b6ff", pixels: [[3, 16, 2, 4], [7, 16, 2, 4], [2, 20, 3, 1], [7, 20, 3, 1]] },
  "legs-hover": { fill: "#84ffe5", pixels: [[2, 17, 8, 1], [1, 18, 10, 1], [3, 19, 2, 1], [7, 19, 2, 1]] },
  "legs-singularity": { fill: "#ffd86b", pixels: [[2, 16, 3, 1], [7, 16, 3, 1], [3, 17, 2, 2], [7, 17, 2, 2], [4, 19, 4, 1]] }
};

const FACES: Record<string, SpritePart> = {
  "face-default": { fill: "transparent", pixels: [] },
  "face-mono":    { fill: "#ffffff", pixels: [[5, 4, 2, 1]] },
  "face-scan":    { fill: "#52e5ff", pixels: [[3, 4, 6, 1]] },
  "face-grin":    { fill: "#9dff9d", pixels: [[4, 6, 1, 1], [5, 7, 2, 1], [7, 6, 1, 1]] },
  "face-frown":   { fill: "#ff9c9c", pixels: [[5, 6, 2, 1], [4, 7, 1, 1], [7, 7, 1, 1]] },
  "face-x":       { fill: "#ff6b6b", pixels: [[4, 3, 1, 1], [6, 3, 1, 1], [5, 4, 1, 1], [4, 5, 1, 1], [6, 5, 1, 1], [8, 3, 1, 1], [9, 4, 1, 1], [8, 5, 1, 1]] },
  "face-star":    { fill: "#ffe266", pixels: [[5, 3, 2, 1], [4, 4, 4, 1], [5, 5, 2, 1]] },
  "face-halo":    { fill: "#ffd86b", pixels: [[4, 0, 1, 1], [5, 0, 2, 1], [7, 0, 1, 1]] }
};

const ACCESSORIES: Record<string, SpritePart> = {
  "acc-none":   { fill: "transparent", pixels: [] },
  "acc-scarf":  { fill: "#ff7eb3", pixels: [[3, 8, 6, 1]] },
  "acc-badge":  { fill: "#ffe266", pixels: [[5, 11, 2, 2]] },
  "acc-cape":   { fill: "#9b8dff", pixels: [[1, 9, 1, 5], [10, 9, 1, 5]] },
  "acc-chain":  { fill: "#d4d4d4", pixels: [[4, 9, 4, 1], [6, 10, 1, 1]] },
  "acc-stripe": { fill: "#52e5ff", pixels: [[2, 10, 8, 1], [3, 12, 6, 1]] },
  "acc-wings":  { fill: "#f3a6ff", pixels: [[0, 10, 2, 2], [10, 10, 2, 2]] },
  "acc-bolt":   { fill: "#ffe266", pixels: [[6, 9, 2, 1], [5, 10, 2, 1], [6, 11, 2, 1], [5, 12, 2, 1]] }
};

export { HEADS, BODIES, LEGS, FACES, ACCESSORIES };
export type { SpritePart, Pixel };

function renderPixels(part: SpritePart, pixelSize: number) {
  return part.pixels.map(([x, y, w = 1, h = 1], index) => (
    <rect
      key={`${part.fill}-${index}`}
      x={x * pixelSize}
      y={y * pixelSize}
      width={w * pixelSize}
      height={h * pixelSize}
      rx={0.5}
      fill={part.fill}
      stroke={part.stroke}
    />
  ));
}

function resolvePart<T extends Record<string, SpritePart>>(catalog: T, id: string | undefined, fallbackKey: keyof T): SpritePart {
  if (id && catalog[id]) {
    return catalog[id];
  }
  return catalog[fallbackKey as string];
}

function resolvePartId(catalog: Record<string, SpritePart>, id: string | undefined, fallbackKey: string): string {
  if (id && catalog[id]) return id;
  return fallbackKey;
}

function useManifest(): SpriteManifest | null {
  const [manifest, setManifest] = useState<SpriteManifest | null>(getManifestSync);

  useEffect(() => {
    if (manifest) return;
    let cancelled = false;
    loadManifest().then((m) => {
      if (!cancelled) setManifest(m);
    });
    return () => { cancelled = true; };
  }, [manifest]);

  return manifest;
}

function usePngAvailable(manifest: SpriteManifest | null, partIds: string[]): boolean {
  if (!manifest) return false;
  return partIds.some((id) => hasPngSprite(manifest, id));
}

function SvgSprite({ parts, animated }: { parts?: any; animated: boolean }) {
  const pixelSize = 4;
  const head = resolvePart(HEADS, parts?.headId, "head-bubble");
  const body = resolvePart(BODIES, parts?.bodyId, "body-core");
  const legs = resolvePart(LEGS, parts?.legsId, "legs-stub");
  const face = resolvePart(FACES, parts?.faceId, "face-default");
  const accessory = resolvePart(ACCESSORIES, parts?.accessoryId, "acc-none");

  return (
    <svg viewBox="0 0 48 88" role="presentation">
      <g className="agent-pet-shadow">
        <ellipse cx="24" cy="82" rx="16" ry="4" fill="rgba(0, 0, 0, 0.28)" />
      </g>
      <g className="agent-pet-legs">{renderPixels(legs, pixelSize)}</g>
      <g className="agent-pet-body">{renderPixels(body, pixelSize)}</g>
      <g className="agent-pet-accessory">{renderPixels(accessory, pixelSize)}</g>
      <g className={animated ? "agent-pet-head is-animated" : "agent-pet-head"}>
        {renderPixels(head, pixelSize)}
      </g>
      <g className={animated ? "agent-pet-face is-animated" : "agent-pet-face"}>
        {renderPixels(face, pixelSize)}
      </g>
    </svg>
  );
}

function PngSprite({ parts, animated, manifest }: { parts?: any; animated: boolean; manifest: SpriteManifest }) {
  const headId = resolvePartId(HEADS, parts?.headId, "head-bubble");
  const bodyId = resolvePartId(BODIES, parts?.bodyId, "body-core");
  const legsId = resolvePartId(LEGS, parts?.legsId, "legs-stub");
  const faceId = resolvePartId(FACES, parts?.faceId, "face-default");
  const accId = resolvePartId(ACCESSORIES, parts?.accessoryId, "acc-none");

  return (
    <div className="agent-pet-png-stack">
      <div className="agent-pet-shadow agent-pet-png-shadow" />
      <div className="agent-pet-legs agent-pet-png-layer">
        <SpriteLayer src={spriteSrc(legsId)} meta={spritePartMeta(manifest, legsId)} />
      </div>
      <div className="agent-pet-body agent-pet-png-layer">
        <SpriteLayer src={spriteSrc(bodyId)} meta={spritePartMeta(manifest, bodyId)} />
      </div>
      <div className={`agent-pet-accessory agent-pet-png-layer ${animated ? "is-animated" : ""}`}>
        <SpriteLayer src={spriteSrc(accId)} meta={spritePartMeta(manifest, accId)} />
      </div>
      <div className={`agent-pet-head agent-pet-png-layer ${animated ? "is-animated" : ""}`}>
        <SpriteLayer src={spriteSrc(headId)} meta={spritePartMeta(manifest, headId)} />
      </div>
      <div className={`agent-pet-face agent-pet-png-layer ${animated ? "is-animated" : ""}`}>
        <SpriteLayer src={spriteSrc(faceId)} meta={spritePartMeta(manifest, faceId)} />
      </div>
    </div>
  );
}

export function AgentPetSprite({ parts, className = "", animated = true }: { parts?: any; className?: string; animated?: boolean }) {
  const manifest = useManifest();
  const headId = resolvePartId(HEADS, parts?.headId, "head-bubble");
  const bodyId = resolvePartId(BODIES, parts?.bodyId, "body-core");
  const legsId = resolvePartId(LEGS, parts?.legsId, "legs-stub");
  const faceId = resolvePartId(FACES, parts?.faceId, "face-default");
  const accId = resolvePartId(ACCESSORIES, parts?.accessoryId, "acc-none");
  const usePng = usePngAvailable(manifest, [headId, bodyId, legsId, faceId, accId]);

  return (
    <div className={`agent-pet-sprite ${className}`.trim()} aria-hidden="true">
      {usePng
        ? <PngSprite parts={parts} animated={animated} manifest={manifest!} />
        : <SvgSprite parts={parts} animated={animated} />
      }
    </div>
  );
}

function SvgIcon({ parts }: { parts?: any }) {
  const pixelSize = 4;
  const head = resolvePart(HEADS, parts?.headId, "head-bubble");
  const face = resolvePart(FACES, parts?.faceId, "face-default");

  return (
    <svg viewBox="8 0 32 32" role="presentation">
      <g>{renderPixels(head, pixelSize)}</g>
      <g>{renderPixels(face, pixelSize)}</g>
    </svg>
  );
}

function PngIcon({ parts, manifest }: { parts?: any; manifest: SpriteManifest }) {
  const headId = resolvePartId(HEADS, parts?.headId, "head-bubble");
  const faceId = resolvePartId(FACES, parts?.faceId, "face-default");

  return (
    <div className="agent-pet-png-icon-stack">
      <div className="agent-pet-png-layer">
        <SpriteLayer src={spriteSrc(headId)} meta={spritePartMeta(manifest, headId)} />
      </div>
      <div className="agent-pet-png-layer">
        <SpriteLayer src={spriteSrc(faceId)} meta={spritePartMeta(manifest, faceId)} />
      </div>
    </div>
  );
}

export function AgentPetIcon({ parts, className = "" }: { parts?: any; className?: string }) {
  const manifest = useManifest();
  const headId = resolvePartId(HEADS, parts?.headId, "head-bubble");
  const faceId = resolvePartId(FACES, parts?.faceId, "face-default");
  const usePng = usePngAvailable(manifest, [headId, faceId]);

  return (
    <div className={`agent-pet-icon ${className}`.trim()} aria-hidden="true">
      {usePng
        ? <PngIcon parts={parts} manifest={manifest!} />
        : <SvgIcon parts={parts} />
      }
    </div>
  );
}
