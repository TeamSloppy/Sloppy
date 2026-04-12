#!/usr/bin/env node
/**
 * Slices the Sloppies modular sheet into 48×88 PNGs that match the SVG pet layout.
 *
 * Source sheet (1024×291): 8 columns × 128px; rows: 72 + 73 + 73 + 73 = 291px.
 * Row 0: faces, row 1: heads, row 2: torsos, row 3: leg bases (cols 0–4 only).
 */
import { createCanvas, loadImage } from "@napi-rs/canvas";
import { mkdirSync, writeFileSync, existsSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SHEET_PATH = join(__dirname, "sloppies-sheet.png");
const OUT_DIR = join(__dirname, "..", "public", "sprites");

const CANVAS_W = 168;
const CANVAS_H = 308;

const COL_W = 190;
const ROW_HEIGHTS = [70 * 2, 70 * 2, 58 * 2, 70 * 2];

const ROW_Y = [];
for (let y = 0, i = 0; i < ROW_HEIGHTS.length; i++) {
  ROW_Y.push(y);
  y += ROW_HEIGHTS[i];
}

/** Same order as `AgentPetFactory` heads (left-to-right on the sheet). */
const HEAD_IDS = [
  "head_vladimir",
  "head_kisya",
  "head_ada",
  "head_bipbop",
  "head_george",
  "head_hollow",
  "head_pooh",
  "head_proj1018_secret",
];

const BODY_IDS = [
  "body-core",
  "body-puff",
  "body-brick",
  "body-terminal",
  "body-satchel",
  "body-relay",
  "body-reactor",
  "body-throne",
];

const LEG_IDS_SHEET = [
  "legs-stub",
  "legs-bouncer",
  "legs-track",
  "legs-sprinter",
  "legs-spider",
];

/** Expression overlays: `face-default` has no art; others use row 0 columns 0–6 (column 7 unused on 8-wide sheet). */
const FACE_IDS = [
  "face-default",
  "face-mono",
  "face-scan",
  "face-grin",
  "face-frown",
  "face-x",
  "face-star",
  "face-halo",
];

const BOX = {
  head: { x: -5, y: -30, w: 190, h: 190 },
  face: { x: 10, y: -15, w: 190, h: 190 },
  body: { x: 10, y: 60, w: 160, h: 190 },
  legs: { x: 2, y: 155, w: 190, h: 190 },
};

function fitContain(box, sw, sh) {
  const aspect = sw / sh;
  let dw = box.w;
  let dh = box.h;
  if (dw / dh > aspect) {
    dw = dh * aspect;
  } else {
    dh = dw / aspect;
  }
  const dx = box.x + (box.w - dw) / 2;
  const dy = box.y + (box.h - dh) / 2;
  return { dx, dy, dw, dh };
}

function drawSlice(ctx, sheet, col, row, box) {
  const sx = col * COL_W;
  const sy = ROW_Y[row];
  const sw = COL_W;
  const sh = ROW_HEIGHTS[row];
  const { dx, dy, dw, dh } = fitContain(box, sw, sh);
  ctx.drawImage(sheet, sx, sy, sw, sh, dx, dy, dw, dh);
}

function emptyCanvas() {
  return createCanvas(CANVAS_W, CANVAS_H);
}

function writePng(path, canvas) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, canvas.toBuffer("image/png"));
}

function loadExistingManifest() {
  const p = join(OUT_DIR, "manifest.json");
  if (!existsSync(p)) return { version: 1, parts: {} };
  return JSON.parse(readFileSync(p, "utf8"));
}

async function main() {
  if (!existsSync(SHEET_PATH)) {
    console.error(`Missing source sheet: ${SHEET_PATH}`);
    process.exit(1);
  }

  const sheet = await loadImage(SHEET_PATH);
  const meta = loadExistingManifest();

  for (let col = 0; col < HEAD_IDS.length; col++) {
    const id = HEAD_IDS[col];
    const canvas = emptyCanvas();
    const ctx = canvas.getContext("2d");
    drawSlice(ctx, sheet, col, 1, BOX.head);
    writePng(join(OUT_DIR, "heads", `${id}.png`), canvas);
    meta.parts[id] = { frames: 1, fps: 0, width: CANVAS_W, height: CANVAS_H };
  }

  const nonDefaultFaces = FACE_IDS.filter((id) => id !== "face-default");
  for (const id of FACE_IDS) {
    const canvas = emptyCanvas();
    const ctx = canvas.getContext("2d");
    if (id !== "face-default") {
      const col = nonDefaultFaces.indexOf(id);
      drawSlice(ctx, sheet, col, 0, BOX.face);
    }
    writePng(join(OUT_DIR, "faces", `${id}.png`), canvas);
    meta.parts[id] = { frames: 1, fps: 0, width: CANVAS_W, height: CANVAS_H };
  }

  for (let col = 0; col < BODY_IDS.length; col++) {
    const id = BODY_IDS[col];
    const canvas = emptyCanvas();
    const ctx = canvas.getContext("2d");
    drawSlice(ctx, sheet, col, 2, BOX.body);
    writePng(join(OUT_DIR, "bodies", `${id}.png`), canvas);
    meta.parts[id] = { frames: 1, fps: 0, width: CANVAS_W, height: CANVAS_H };
  }

  for (let col = 0; col < LEG_IDS_SHEET.length; col++) {
    const id = LEG_IDS_SHEET[col];
    const canvas = emptyCanvas();
    const ctx = canvas.getContext("2d");
    drawSlice(ctx, sheet, col, 3, BOX.legs);
    writePng(join(OUT_DIR, "legs", `${id}.png`), canvas);
    meta.parts[id] = { frames: 1, fps: 0, width: CANVAS_W, height: CANVAS_H };
  }

  writeFileSync(join(OUT_DIR, "manifest.json"), JSON.stringify(meta, null, 2) + "\n");
  console.log(
    `Sliced sheet → heads×${HEAD_IDS.length}, faces×${FACE_IDS.length}, bodies×${BODY_IDS.length}, legs×${LEG_IDS_SHEET.length}; manifest merged.`,
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
