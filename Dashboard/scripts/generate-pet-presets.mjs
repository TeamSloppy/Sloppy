#!/usr/bin/env node
import { createCanvas } from "@napi-rs/canvas";
import { mkdirSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, "..", "public", "pets");

const SHEET_W = 1024;
const SHEET_H = 1536;
const CELL = 256;
const LOW_CELL = 64;
const COLS = 4;

const COMMON = {
  outline: "#1c1730",
  outlineSoft: "#342b49",
  shadow: "#5b5168",
  cream: "#fff0c7",
  blush: "#f27f9b",
  eye: "#181326",
  shine: "#ffffff",
};

const presets = [
  {
    id: "aurora-bun",
    name: "Aurora Bun",
    kind: "bun",
    colors: {
      main: "#7ddfed",
      shade: "#49aeca",
      accent: "#f5a6d5",
      accent2: "#f6e76e",
    },
  },
  {
    id: "spark-fox",
    name: "Spark Fox",
    kind: "fox",
    colors: {
      main: "#f39a45",
      shade: "#c46331",
      accent: "#f6d25b",
      accent2: "#5fd7e8",
    },
  },
  {
    id: "moss-moth",
    name: "Moss Moth",
    kind: "moth",
    colors: {
      main: "#86cf8b",
      shade: "#5b9d74",
      accent: "#e6c86e",
      accent2: "#b59af3",
    },
  },
];

const ranges = {
  idle: [0, 3],
  walk: [4, 7],
  happy: [8, 11],
  sad: [12, 15],
  interacted: [16, 18],
  sleep: [19, 21],
  avatar: [22, 22],
};

function frameState(frame) {
  for (const [state, [start, end]] of Object.entries(ranges)) {
    if (frame >= start && frame <= end) return state;
  }
  return "idle";
}

function stateIndex(frame) {
  const state = frameState(frame);
  return frame - ranges[state][0];
}

function rect(ctx, x, y, w, h, fill) {
  ctx.fillStyle = fill;
  ctx.fillRect(Math.round(x), Math.round(y), Math.round(w), Math.round(h));
}

function outlinedRect(ctx, x, y, w, h, fill, outline = COMMON.outline) {
  rect(ctx, x - 1, y - 1, w + 2, h + 2, outline);
  rect(ctx, x, y, w, h, fill);
}

function blockBlob(ctx, cx, y, rows, fill, outline = COMMON.outline, rowHeight = 2) {
  rows.forEach((width, index) => {
    const x = cx - width / 2;
    rect(ctx, x - 1, y + index * rowHeight - 1, width + 2, rowHeight + 2, outline);
  });
  rows.forEach((width, index) => {
    const x = cx - width / 2;
    rect(ctx, x, y + index * rowHeight, width, rowHeight, fill);
  });
}

function stepTriangle(ctx, x, y, widths, fill, outline = COMMON.outline, rowHeight = 2) {
  widths.forEach((width, index) => {
    rect(ctx, x - width / 2 - 1, y + index * rowHeight - 1, width + 2, rowHeight + 2, outline);
  });
  widths.forEach((width, index) => {
    rect(ctx, x - width / 2, y + index * rowHeight, width, rowHeight, fill);
  });
}

function face(ctx, cx, y, state, colors) {
  if (state === "sleep") {
    rect(ctx, cx - 8, y, 5, 1, COMMON.eye);
    rect(ctx, cx + 3, y, 5, 1, COMMON.eye);
    rect(ctx, cx - 2, y + 6, 4, 1, COMMON.eye);
    return;
  }

  if (state === "happy" || state === "interacted") {
    rect(ctx, cx - 8, y, 2, 2, COMMON.eye);
    rect(ctx, cx - 6, y + 2, 2, 1, COMMON.eye);
    rect(ctx, cx + 6, y, 2, 2, COMMON.eye);
    rect(ctx, cx + 4, y + 2, 2, 1, COMMON.eye);
    rect(ctx, cx - 3, y + 7, 6, 1, COMMON.eye);
    rect(ctx, cx - 2, y + 8, 4, 1, COMMON.eye);
    rect(ctx, cx - 12, y + 6, 3, 2, COMMON.blush);
    rect(ctx, cx + 9, y + 6, 3, 2, COMMON.blush);
    return;
  }

  if (state === "sad") {
    rect(ctx, cx - 8, y + 1, 3, 3, COMMON.eye);
    rect(ctx, cx + 5, y + 1, 3, 3, COMMON.eye);
    rect(ctx, cx - 3, y + 8, 6, 1, COMMON.eye);
    rect(ctx, cx - 4, y + 9, 1, 1, COMMON.eye);
    rect(ctx, cx + 3, y + 9, 1, 1, COMMON.eye);
    rect(ctx, cx + 9, y + 4, 1, 3, colors.accent2);
    return;
  }

  rect(ctx, cx - 8, y, 4, 4, COMMON.eye);
  rect(ctx, cx + 4, y, 4, 4, COMMON.eye);
  rect(ctx, cx - 7, y, 1, 1, COMMON.shine);
  rect(ctx, cx + 5, y, 1, 1, COMMON.shine);
  rect(ctx, cx - 3, y + 8, 6, 1, COMMON.eye);
}

function drawShadow(ctx, cx, y, width) {
  rect(ctx, cx - width / 2, y, width, 2, COMMON.shadow);
  rect(ctx, cx - width / 2 + 4, y + 2, width - 8, 1, COMMON.shadow);
}

function poseFor(frame) {
  const state = frameState(frame);
  const index = stateIndex(frame);
  const cycle = [0, -2, -1, 1][frame % 4] || 0;
  const walk = [-2, 1, 2, -1][index % 4] || 0;
  return {
    state,
    index,
    bounce: state === "sleep" || state === "avatar" ? 0 : cycle,
    sway: state === "walk" ? walk : 0,
    wing: state === "happy" || state === "interacted" ? index % 2 : 0,
  };
}

function drawAuroraBun(ctx, stage, frame) {
  const { state, bounce, sway, index } = poseFor(frame);
  const c = presets[0].colors;
  const cx = 32 + sway;
  const base = 48 + bounce;
  const bodyRows = stage === 1
    ? [14, 20, 24, 26, 24, 20, 14]
    : stage === 2
      ? [18, 24, 30, 32, 32, 28, 22, 14]
      : [22, 30, 36, 38, 38, 34, 28, 18];
  const bodyTop = base - bodyRows.length * 2 - 4;

  drawShadow(ctx, 32, 56, stage === 1 ? 24 : stage === 2 ? 30 : 36);

  const earLift = state === "happy" ? -2 : state === "sad" ? 2 : 0;
  const earH = stage === 1 ? 17 : stage === 2 ? 22 : 25;
  outlinedRect(ctx, cx - 14, bodyTop - earH + earLift, 6, earH, c.main);
  outlinedRect(ctx, cx + 8, bodyTop - earH + earLift + (state === "sleep" ? 2 : 0), 6, earH, c.main);
  rect(ctx, cx - 12, bodyTop - earH + 4 + earLift, 2, earH - 8, c.accent);
  rect(ctx, cx + 10, bodyTop - earH + 4 + earLift, 2, earH - 8, c.accent);
  if (stage >= 3) {
    rect(ctx, cx - 16, bodyTop - earH + 5, 2, 4, c.accent2);
    rect(ctx, cx + 14, bodyTop - earH + 8, 2, 4, c.accent2);
  }

  blockBlob(ctx, cx, bodyTop, bodyRows, c.main);
  rect(ctx, cx - 9, bodyTop + 8, 18, bodyRows.length + 1, c.shade);
  blockBlob(ctx, cx, bodyTop + 9, stage === 1 ? [10, 12, 10] : [12, 16, 16, 12], COMMON.cream);
  face(ctx, cx, bodyTop + 8, state, c);

  rect(ctx, cx - 12, base - 3 + (index % 2), 6, 3, COMMON.outlineSoft);
  rect(ctx, cx + 6, base - 3 + ((index + 1) % 2), 6, 3, COMMON.outlineSoft);
  if (stage >= 2) rect(ctx, cx - 17, bodyTop + 15, 5, 5, c.accent2);
  if (stage >= 3) {
    rect(ctx, cx + 13, bodyTop + 12, 4, 13, c.accent);
    rect(ctx, cx + 16, bodyTop + 16, 3, 5, c.accent2);
  }
}

function drawSparkFox(ctx, stage, frame) {
  const { state, bounce, sway, index } = poseFor(frame);
  const c = presets[1].colors;
  const cx = 31 + sway;
  const base = 49 + bounce;
  const headTop = stage === 1 ? 21 : stage === 2 ? 17 : 14;
  const bodyRows = stage === 1
    ? [12, 18, 22, 22, 18, 12]
    : stage === 2
      ? [16, 22, 26, 28, 26, 20, 12]
      : [18, 26, 32, 34, 34, 28, 20, 12];
  const bodyTop = base - bodyRows.length * 2 - 2;

  drawShadow(ctx, 32, 56, stage === 1 ? 24 : stage === 2 ? 32 : 38);

  const tailX = cx + (stage === 1 ? 13 : 17);
  const tailRows = stage === 1 ? [5, 8, 11, 13, 10, 6] : stage === 2 ? [7, 11, 16, 18, 15, 10, 5] : [9, 14, 20, 22, 19, 14, 8, 4];
  blockBlob(ctx, tailX + (index % 2), bodyTop + (stage === 1 ? 4 : 0), tailRows, c.accent);
  rect(ctx, tailX + 2, bodyTop + 4, 6, 8, COMMON.cream);

  stepTriangle(ctx, cx - 10, headTop, [3, 7, 11, 15], c.main);
  stepTriangle(ctx, cx + 10, headTop, [3, 7, 11, 15], c.main);
  rect(ctx, cx - 11, headTop + 7, 5, 4, c.accent);
  rect(ctx, cx + 6, headTop + 7, 5, 4, c.accent);

  blockBlob(ctx, cx, bodyTop, bodyRows, c.main);
  rect(ctx, cx - 10, bodyTop + 10, 20, bodyRows.length + 2, c.shade);
  blockBlob(ctx, cx, bodyTop + 10, stage === 1 ? [8, 10, 8] : [10, 14, 14, 10], COMMON.cream);
  if (stage >= 2) {
    rect(ctx, cx - 17, bodyTop + 12, 5, 10, c.accent2);
    rect(ctx, cx - 18, bodyTop + 16, 7, 2, COMMON.outline);
  }
  if (stage >= 3) {
    rect(ctx, cx + 11, bodyTop + 5, 4, 13, c.accent);
    rect(ctx, cx + 8, bodyTop + 12, 7, 4, COMMON.outline);
    rect(ctx, cx + 10, bodyTop + 13, 3, 2, c.accent2);
  }
  face(ctx, cx, bodyTop + 7, state, c);
  rect(ctx, cx - 13, base - 3 + (index % 2), 7, 3, COMMON.outlineSoft);
  rect(ctx, cx + 4, base - 3 + ((index + 1) % 2), 7, 3, COMMON.outlineSoft);
}

function drawMossMoth(ctx, stage, frame) {
  const { state, bounce, sway, index, wing } = poseFor(frame);
  const c = presets[2].colors;
  const cx = 32 + sway;
  const base = 49 + bounce;
  const bodyRows = stage === 1
    ? [12, 18, 22, 22, 18, 12]
    : stage === 2
      ? [14, 20, 24, 26, 24, 18, 12]
      : [16, 22, 28, 30, 30, 24, 18, 10];
  const bodyTop = base - bodyRows.length * 2 - 3;

  drawShadow(ctx, 32, 56, stage === 1 ? 26 : stage === 2 ? 34 : 42);

  const wingRows = stage === 1 ? [8, 12, 14, 12, 8] : stage === 2 ? [10, 16, 20, 22, 18, 12] : [12, 20, 26, 30, 28, 22, 14];
  blockBlob(ctx, cx - (stage === 1 ? 12 : 17), bodyTop + 5 - wing, wingRows, c.accent);
  blockBlob(ctx, cx + (stage === 1 ? 12 : 17), bodyTop + 5 + wing, wingRows, c.accent);
  rect(ctx, cx - (stage === 1 ? 16 : 23), bodyTop + 12, 7, 3, c.accent2);
  rect(ctx, cx + (stage === 1 ? 9 : 16), bodyTop + 12, 7, 3, c.accent2);

  const antennaY = bodyTop - (stage === 1 ? 8 : stage === 2 ? 11 : 14);
  rect(ctx, cx - 8, antennaY + 4, 2, 9, COMMON.outline);
  rect(ctx, cx + 6, antennaY + 4, 2, 9, COMMON.outline);
  rect(ctx, cx - 13, antennaY + 2, 7, 2, COMMON.outline);
  rect(ctx, cx + 6, antennaY + 2, 7, 2, COMMON.outline);
  rect(ctx, cx - 14, antennaY, 4, 4, c.accent2);
  rect(ctx, cx + 10, antennaY, 4, 4, c.accent2);

  blockBlob(ctx, cx, bodyTop, bodyRows, c.main);
  rect(ctx, cx - 8, bodyTop + 9, 16, bodyRows.length + 2, c.shade);
  if (stage >= 2) {
    rect(ctx, cx - 3, bodyTop + 20, 6, 3, c.accent);
    rect(ctx, cx - 2, bodyTop + 24, 4, 3, c.accent);
  }
  if (stage >= 3) {
    rect(ctx, cx - 12, bodyTop + 6, 4, 4, c.accent2);
    rect(ctx, cx + 8, bodyTop + 6, 4, 4, c.accent2);
    rect(ctx, cx - 5, bodyTop + 28, 10, 2, COMMON.cream);
  }
  face(ctx, cx, bodyTop + 8, state, c);
  rect(ctx, cx - 12, base - 3 + (index % 2), 7, 3, COMMON.outlineSoft);
  rect(ctx, cx + 5, base - 3 + ((index + 1) % 2), 7, 3, COMMON.outlineSoft);
}

function drawPet(ctx, preset, stage, frame) {
  if (frame === 23) return;
  if (preset.kind === "bun") {
    drawAuroraBun(ctx, stage, frame);
  } else if (preset.kind === "fox") {
    drawSparkFox(ctx, stage, frame);
  } else {
    drawMossMoth(ctx, stage, frame);
  }
}

function drawCellToSheet(sheetCtx, preset, stage, frame) {
  const low = createCanvas(LOW_CELL, LOW_CELL);
  const lowCtx = low.getContext("2d");
  lowCtx.imageSmoothingEnabled = false;
  lowCtx.clearRect(0, 0, LOW_CELL, LOW_CELL);
  drawPet(lowCtx, preset, stage, frame);

  const col = frame % COLS;
  const row = Math.floor(frame / COLS);
  sheetCtx.imageSmoothingEnabled = false;
  sheetCtx.drawImage(low, col * CELL, row * CELL, CELL, CELL);
}

const manifest = {
  version: 1,
  grid: { columns: 4, rows: 6, cellWidth: 256, cellHeight: 256 },
  frameLayout: {
    idle: [0, 3],
    walk: [4, 7],
    happy: [8, 11],
    sad: [12, 15],
    interacted: [16, 18],
    sleep: [19, 21],
    avatar: [22, 22],
  },
  presets: [],
};

for (const preset of presets) {
  const dir = join(OUT_DIR, "presets", preset.id);
  mkdirSync(dir, { recursive: true });
  manifest.presets.push({
    speciesId: preset.id,
    displayName: preset.name,
    stageCount: 3,
    assetBaseURL: `/pets/presets/${preset.id}`,
  });

  for (let stage = 1; stage <= 3; stage++) {
    const canvas = createCanvas(SHEET_W, SHEET_H);
    const ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    ctx.clearRect(0, 0, SHEET_W, SHEET_H);
    for (let frame = 0; frame < 23; frame++) {
      drawCellToSheet(ctx, preset, stage, frame);
    }
    writeFileSync(join(dir, `${stage}.png`), canvas.toBuffer("image/png"));
  }
}

writeFileSync(join(OUT_DIR, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
console.log("Generated pixel-art pet preset sprite sheets.");
