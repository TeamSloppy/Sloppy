#!/usr/bin/env node
import { createCanvas } from "@napi-rs/canvas";
import { mkdirSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, "..", "public", "sprites");

const CANVAS_W = 48;
const CANVAS_H = 88;
const PX = 4;

const HEADS = {
  "head-bubble": { fill: "#9ff3ff", pixels: [[4,0,4,1],[3,1,6,2],[2,3,8,3],[3,6,6,1],[4,7,4,1],[2,4,1,1],[9,4,1,1],[4,4,1,1],[7,4,1,1]] },
  "head-cube": { fill: "#c3ffd0", pixels: [[3,1,6,1],[2,2,8,5],[3,7,6,1],[4,4,1,1],[7,4,1,1]] },
  "head-shell": { fill: "#f9d69f", pixels: [[4,0,4,1],[3,1,6,1],[2,2,8,1],[1,3,10,3],[2,6,8,1],[3,7,6,1],[4,4,1,1],[7,4,1,1]] },
  "head-fork": { fill: "#f3a6ff", pixels: [[3,0,1,2],[8,0,1,2],[4,1,4,1],[2,2,8,5],[4,4,1,1],[7,4,1,1]] },
  "head-visor": { fill: "#9fb4ff", pixels: [[3,1,6,1],[2,2,8,4],[3,6,6,2],[3,3,6,2],[4,7,1,1],[7,7,1,1]] },
  "head-probe": { fill: "#ffb27a", pixels: [[5,0,2,1],[6,1,1,1],[3,2,6,5],[4,4,1,1],[7,4,1,1],[2,5,1,1],[9,5,1,1]] },
  "head-oracle": { fill: "#9df0ce", pixels: [[5,0,2,1],[4,1,4,1],[3,2,6,1],[2,3,8,4],[3,7,6,1],[4,4,1,1],[7,4,1,1],[5,6,2,1]] },
  "head-crown": { fill: "#ffe266", pixels: [[2,1,2,1],[5,0,2,1],[8,1,2,1],[3,2,6,1],[2,3,8,4],[4,4,1,1],[7,4,1,1],[3,7,6,1]] },
};

const BODIES = {
  "body-core": { fill: "#78d7ff", pixels: [[4,8,4,1],[3,9,6,1],[2,10,8,4],[3,14,6,1]] },
  "body-puff": { fill: "#f8b6d2", pixels: [[3,8,6,1],[2,9,8,1],[1,10,10,3],[2,13,8,2],[4,11,1,1],[7,11,1,1]] },
  "body-brick": { fill: "#cbb7ff", pixels: [[3,8,6,1],[2,9,8,5],[3,14,6,1],[4,10,4,1],[4,12,4,1]] },
  "body-terminal": { fill: "#90ffac", pixels: [[2,8,8,1],[1,9,10,5],[2,14,8,1],[3,10,6,2],[3,12,2,1],[7,12,2,1]] },
  "body-satchel": { fill: "#ffcf8d", pixels: [[3,8,6,1],[2,9,8,5],[3,14,6,1],[8,11,2,2],[1,10,1,3]] },
  "body-relay": { fill: "#ff9c9c", pixels: [[3,8,6,1],[2,9,8,2],[1,11,10,2],[2,13,8,2],[4,10,1,1],[7,10,1,1]] },
  "body-reactor": { fill: "#82f3d9", pixels: [[4,8,4,1],[3,9,6,1],[2,10,8,5],[4,11,4,2],[5,15,2,1]] },
  "body-throne": { fill: "#ffdd78", pixels: [[2,8,8,1],[1,9,10,6],[3,10,6,1],[4,11,4,2],[3,15,6,1]] },
};

const LEGS = {
  "legs-stub": { fill: "#8fc2ff", pixels: [[3,16,2,3],[7,16,2,3]] },
  "legs-bouncer": { fill: "#c9ff9b", pixels: [[3,16,2,2],[2,18,3,1],[7,16,2,2],[7,18,3,1]] },
  "legs-track": { fill: "#ffc9a8", pixels: [[2,16,8,1],[1,17,10,2]] },
  "legs-sprinter": { fill: "#ffb1f1", pixels: [[3,16,1,3],[4,18,2,1],[8,16,1,3],[6,18,2,1]] },
  "legs-spider": { fill: "#99f0ff", pixels: [[2,16,2,1],[1,17,2,1],[3,18,2,1],[8,16,2,1],[9,17,2,1],[7,18,2,1]] },
  "legs-piston": { fill: "#e4b6ff", pixels: [[3,16,2,4],[7,16,2,4],[2,20,3,1],[7,20,3,1]] },
  "legs-hover": { fill: "#84ffe5", pixels: [[2,17,8,1],[1,18,10,1],[3,19,2,1],[7,19,2,1]] },
  "legs-singularity": { fill: "#ffd86b", pixels: [[2,16,3,1],[7,16,3,1],[3,17,2,2],[7,17,2,2],[4,19,4,1]] },
};

const FACES = {
  "face-default": { fill: "transparent", pixels: [] },
  "face-mono": { fill: "#ffffff", pixels: [[5,4,2,1]] },
  "face-scan": { fill: "#52e5ff", pixels: [[3,4,6,1]] },
  "face-grin": { fill: "#9dff9d", pixels: [[4,6,1,1],[5,7,2,1],[7,6,1,1]] },
  "face-frown": { fill: "#ff9c9c", pixels: [[5,6,2,1],[4,7,1,1],[7,7,1,1]] },
  "face-x": { fill: "#ff6b6b", pixels: [[4,3,1,1],[6,3,1,1],[5,4,1,1],[4,5,1,1],[6,5,1,1],[8,3,1,1],[9,4,1,1],[8,5,1,1]] },
  "face-star": { fill: "#ffe266", pixels: [[5,3,2,1],[4,4,4,1],[5,5,2,1]] },
  "face-halo": { fill: "#ffd86b", pixels: [[4,0,1,1],[5,0,2,1],[7,0,1,1]] },
};

const ACCESSORIES = {
  "acc-none": { fill: "transparent", pixels: [] },
  "acc-scarf": { fill: "#ff7eb3", pixels: [[3,8,6,1]] },
  "acc-badge": { fill: "#ffe266", pixels: [[5,11,2,2]] },
  "acc-cape": { fill: "#9b8dff", pixels: [[1,9,1,5],[10,9,1,5]] },
  "acc-chain": { fill: "#d4d4d4", pixels: [[4,9,4,1],[6,10,1,1]] },
  "acc-stripe": { fill: "#52e5ff", pixels: [[2,10,8,1],[3,12,6,1]] },
  "acc-wings": { fill: "#f3a6ff", pixels: [[0,10,2,2],[10,10,2,2]] },
  "acc-bolt": { fill: "#ffe266", pixels: [[6,9,2,1],[5,10,2,1],[6,11,2,1],[5,12,2,1]] },
};

const CATEGORIES = [
  { folder: "heads", parts: HEADS },
  { folder: "bodies", parts: BODIES },
  { folder: "legs", parts: LEGS },
  { folder: "faces", parts: FACES },
  { folder: "accessories", parts: ACCESSORIES },
];

function renderPart(partData) {
  const canvas = createCanvas(CANVAS_W, CANVAS_H);
  const ctx = canvas.getContext("2d");

  if (partData.fill === "transparent" || partData.pixels.length === 0) {
    return canvas.toBuffer("image/png");
  }

  ctx.fillStyle = partData.fill;
  for (const [x, y, w = 1, h = 1] of partData.pixels) {
    ctx.fillRect(x * PX, y * PX, w * PX, h * PX);
  }

  return canvas.toBuffer("image/png");
}

const manifest = { version: 1, parts: {} };
let total = 0;

for (const { folder, parts } of CATEGORIES) {
  const dir = join(OUT_DIR, folder);
  mkdirSync(dir, { recursive: true });

  for (const [id, data] of Object.entries(parts)) {
    const buf = renderPart(data);
    const filePath = join(dir, `${id}.png`);
    writeFileSync(filePath, buf);

    manifest.parts[id] = { frames: 1, fps: 0, width: CANVAS_W, height: CANVAS_H };
    total++;
  }
}

writeFileSync(join(OUT_DIR, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
console.log(`Generated ${total} placeholder sprites + manifest.json`);
