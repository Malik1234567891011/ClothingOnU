// End-to-end quality harness against the real model.
//   npm run eval -- <case> [--fast] [--steps avatar,tryon,side,back]
// Cases live in testdata/cases.json (gitignored with the photos). Each step's output is saved
// to testdata/out/<case>/ and reused by later steps, so you can re-run one step cheaply.
//
// Images are resized with macOS `sips` to what the iOS client sends (1280 px long edge JPEG).

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { handleRender } from "../lib/handler.ts";
import type { Build, Garment, ImageData, Photo, RenderResponse } from "../lib/types.ts";

interface Case {
  heightCm: number;
  build: Build;
  photos: { role: Photo["role"]; file: string }[];
  garments: { slot: Garment["slot"]; file: string }[];
  note?: string;
}

const root = resolve(import.meta.dirname, "../../testdata");
const args = process.argv.slice(2);
const name = args.find((a) => !a.startsWith("--"));
const quality = args.includes("--fast") ? "fast" : "pro";
const stepsArg = args[args.indexOf("--steps") + 1];
const steps = args.includes("--steps") && stepsArg ? stepsArg.split(",") : ["avatar", "tryon", "side", "back"];

const cases = JSON.parse(readFileSync(join(root, "cases.json"), "utf8")) as Record<string, Case>;
if (!name || !cases[name]) {
  console.error(`usage: npm run eval -- <case>   cases: ${Object.keys(cases).join(", ")}`);
  process.exit(1);
}
const c = cases[name]!;
const outDir = join(root, "out", name);
mkdirSync(outDir, { recursive: true });

function load(file: string, maxEdge = 1280): ImageData {
  const tmp = join(outDir, `.in-${file.replace(/\W/g, "_")}.jpg`);
  execFileSync("sips", ["-s", "format", "jpeg", "-s", "formatOptions", "80", "-Z", String(maxEdge), join(root, file), "--out", tmp], { stdio: "ignore" });
  return { mimeType: "image/jpeg", data: readFileSync(tmp).toString("base64") };
}
const saved = (n: string): ImageData => ({ mimeType: "image/jpeg", data: readFileSync(join(outDir, n)).toString("base64") });

const profile = { heightCm: c.heightCm, build: c.build };
const photos = c.photos.map((p) => ({ role: p.role, ...load(p.file) }));
const garments = c.garments.map((g) => ({ slot: g.slot, ...load(g.file) }));

async function render(step: string, body: Record<string, unknown>, out: string) {
  const req = new Request("http://local/api/render", { method: "POST", body: JSON.stringify({ quality, profile, photos, ...body }) });
  const res = await handleRender(req, { appToken: "", log: () => {} });
  const json = (await res.json()) as RenderResponse | { error: { code: string; message: string } };
  if ("error" in json) throw new Error(`${step}: ${json.error.code} ${json.error.message}`);
  writeFileSync(join(outDir, out), Buffer.from(json.image.data, "base64"));
  console.log(`${step.padEnd(7)} ${json.model.padEnd(24)} ${(json.ms / 1000).toFixed(1)}s -> out/${name}/${out}`);
}

for (const step of steps) {
  if (step === "avatar") await render(step, { kind: "avatar" }, "1-avatar.jpg");
  else if (step === "tryon") {
    if (!existsSync(join(outDir, "1-avatar.jpg"))) throw new Error("run avatar first");
    await render(step, { kind: "tryon", base: saved("1-avatar.jpg"), garments, note: c.note }, "2-tryon.jpg");
  } else if (step === "threeQuarter" || step === "side" || step === "back") {
    await render(step, { kind: "view", view: step, anchor: saved("2-tryon.jpg"), garments, note: c.note }, `3-${step}.jpg`);
  }
}
