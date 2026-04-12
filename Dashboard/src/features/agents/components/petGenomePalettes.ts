/**
 * Per-part palettes (8 swatches each). Genome picks one index per slot independently.
 * Tune hex values here — rendering uses HSL hue → CSS filter (sepia + hue-rotate).
 */

export type PetGenomePartSlot = "head" | "face" | "body" | "legs" | "acc";

/** Helmet / casing — acid reds / hot magenta */
export const PET_HEAD_COLORS = [
  "#ff0055",
  "#ff0a6a",
  "#ff1744",
  "#ff3366",
  "#ff006e",
  "#f72585",
  "#ff4d6d",
  "#e0005c",
] as const;

/** Face / “eyes” overlay — toxic / lime / mint */
export const PET_FACE_COLORS = [
  "#39ff14",
  "#00ff41",
  "#ccff00",
  "#00ffa3",
  "#7fff00",
  "#00ff88",
  "#b8ff00",
  "#00ffcc",
] as const;

/** Torso — electric blues / cyans */
export const PET_BODY_COLORS = [
  "#00f5ff",
  "#00d9ff",
  "#00b4ff",
  "#0080ff",
  "#00fff7",
  "#22d3ee",
  "#38bdf8",
  "#00e5ff",
] as const;

/** Legs / base — acid orange / mango / gold */
export const PET_LEGS_COLORS = [
  "#ff6600",
  "#ff8800",
  "#ffaa00",
  "#ff9500",
  "#ffb000",
  "#ff7700",
  "#ffc800",
  "#ff5500",
] as const;

/** Accessory — electric violet / magenta */
export const PET_ACC_COLORS = [
  "#d946ef",
  "#e879f9",
  "#f0abfc",
  "#c026d3",
  "#ff00ff",
  "#a855f7",
  "#e040fb",
  "#f472b6",
] as const;

export const PET_PART_COLOR_PALETTES: Record<PetGenomePartSlot, readonly string[]> = {
  head: PET_HEAD_COLORS,
  face: PET_FACE_COLORS,
  body: PET_BODY_COLORS,
  legs: PET_LEGS_COLORS,
  acc: PET_ACC_COLORS,
};

const SLOT_SALT: Record<PetGenomePartSlot, string> = {
  head: "head:v1",
  face: "face:v1",
  body: "body:v1",
  legs: "legs:v1",
  acc: "acc:v1",
};

/** Deterministic index 0..7 for this genome and body part. */
export function genomeSlotIndex(genomeHex: string | undefined, slot: PetGenomePartSlot): number {
  if (!genomeHex?.trim()) return 0;
  const clean = genomeHex.replace(/^0x/i, "").replace(/\s/g, "");
  if (clean.length < 4) return 0;
  const salt = SLOT_SALT[slot];
  let acc = 0;
  for (let i = 0; i < clean.length; i++) {
    const v = parseInt(clean[i], 16);
    if (!Number.isNaN(v)) {
      acc = (acc * 17 + v * (i + 1) + salt.charCodeAt(i % salt.length)) >>> 0;
    }
  }
  for (let i = 0; i < salt.length; i++) {
    acc = (acc + salt.charCodeAt(i) * (i + 11)) >>> 0;
  }
  return acc % 8;
}

function hueFromHex(hex: string): number {
  const h = hex.replace(/^#/, "");
  if (h.length !== 6) return 0;
  const r = parseInt(h.slice(0, 2), 16) / 255;
  const g = parseInt(h.slice(2, 4), 16) / 255;
  const b = parseInt(h.slice(4, 6), 16) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const d = max - min;
  if (d < 1e-6) return 0;
  let hue = 0;
  if (max === r) {
    hue = ((g - b) / d + (g < b ? 6 : 0)) / 6;
  } else if (max === g) {
    hue = ((b - r) / d + 2) / 6;
  } else {
    hue = ((r - g) / d + 4) / 6;
  }
  return hue * 360;
}

/** Maps a palette swatch to a CSS filter for raster / SVG tinting. */
export function tintFilterFromPaletteHex(hex: string): string {
  const h = Math.round(hueFromHex(hex));
  return `sepia(100%) saturate(250%) hue-rotate(${h}deg) brightness(1.03)`;
}

export function tintFilterForGenomeSlot(
  genomeHex: string | undefined,
  slot: PetGenomePartSlot,
): string | undefined {
  if (!genomeHex?.trim()) return undefined;
  const i = genomeSlotIndex(genomeHex, slot);
  const hex = PET_PART_COLOR_PALETTES[slot][i];
  return tintFilterFromPaletteHex(hex);
}
