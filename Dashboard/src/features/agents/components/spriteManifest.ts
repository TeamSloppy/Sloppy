export interface SpritePartMeta {
  frames: number;
  fps: number;
  width: number;
  height: number;
}

export interface SpriteManifest {
  version: number;
  parts: Record<string, SpritePartMeta>;
}

const SPRITE_BASE = "/sprites";
const MANIFEST_URL = `${SPRITE_BASE}/manifest.json`;

const CATEGORY_MAP: Record<string, string> = {
  head: "heads",
  body: "bodies",
  legs: "legs",
  face: "faces",
  acc: "accessories",
};

let cached: SpriteManifest | null = null;
let fetchPromise: Promise<SpriteManifest> | null = null;

async function fetchManifest(): Promise<SpriteManifest> {
  try {
    const res = await fetch(MANIFEST_URL);
    if (!res.ok) return { version: 0, parts: {} };
    return (await res.json()) as SpriteManifest;
  } catch {
    return { version: 0, parts: {} };
  }
}

export function loadManifest(): Promise<SpriteManifest> {
  if (cached) return Promise.resolve(cached);
  if (!fetchPromise) {
    fetchPromise = fetchManifest().then((m) => {
      cached = m;
      return m;
    });
  }
  return fetchPromise;
}

export function getManifestSync(): SpriteManifest | null {
  return cached;
}

function categoryFolder(partId: string): string {
  const prefix = partId.split("-")[0];
  return CATEGORY_MAP[prefix] || prefix;
}

export function hasPngSprite(manifest: SpriteManifest, partId: string): boolean {
  return partId in manifest.parts;
}

export function spriteSrc(partId: string): string {
  return `${SPRITE_BASE}/${categoryFolder(partId)}/${partId}.png`;
}

export function spritePartMeta(
  manifest: SpriteManifest,
  partId: string
): SpritePartMeta | null {
  return manifest.parts[partId] ?? null;
}
