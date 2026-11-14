// Generates the onboarding demo images: a FICTIONAL person (never a real one, since these ship in
// the app bundle and a public repo) before/after a try-on, from the front and the back.
//   npm run demo-assets   -> ../testdata/demo/*.jpg
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { execFileSync } from "node:child_process";
import { configFromEnv, generateImage } from "../lib/gemini.js";
import { buildTryOnParts, buildViewParts } from "../lib/prompts.js";
import type { ImageData } from "../lib/types.js";

const root = resolve(import.meta.dirname, "../../testdata");
const out = join(root, "demo");
mkdirSync(out, { recursive: true });
const cfg = configFromEnv();
const save = (n: string, i: ImageData) => writeFileSync(join(out, n), Buffer.from(i.data, "base64"));
const shrink = (file: string): ImageData => {
  const tmp = join(out, `.small-${file.replace(/\W/g, "_")}.jpg`);
  execFileSync("sips", ["-s", "format", "jpeg", "-s", "formatOptions", "80", "-Z", "1280", file, "--out", tmp], { stdio: "ignore" });
  return { mimeType: "image/jpeg", data: readFileSync(tmp).toString("base64") };
};

const { image: base } = await generateImage(cfg, [{
  text: "Photorealistic full-length fashion photo of a fictional, non-famous person in their mid twenties with a warm friendly face, " +
    "curly dark hair, light brown skin, average build. Plain well-fitted heather-grey crew-neck t-shirt with no logo, plain black straight-leg trousers, plain white low-top sneakers. " +
    "Standing straight facing the camera, relaxed, arms hanging naturally. Shot on a 50mm lens at chest height. Seamless warm light-grey studio backdrop, soft even light, gentle floor shadow. " +
    "Whole body visible head to toe with a small margin, centred, 3:4 portrait. No text, no watermark.",
}], "pro");
save("demo-base.jpg", base);
console.log("base ok");

const profile = { heightCm: 175, build: "average" as const };
const photos = [{ role: "front" as const, ...base }];
const garments = [
  { slot: "outer" as const, ...shrink(join(root, "garments/uniqlo_striped_sweater_crop.jpg")) },
  { slot: "bottom" as const, ...shrink(join(root, "garments/uniqlo_barrel_jeans.jpg")) },
];
// The sweater is used as an outer layer over the tee here on purpose: it shows layering in the demo.
const { image: look } = await generateImage(cfg, buildTryOnParts({ kind: "tryon", profile, photos, base, garments, quality: "pro" }), "pro");
save("demo-look.jpg", look);
console.log("look ok");
const { image: back } = await generateImage(cfg, buildViewParts({ kind: "view", view: "back", profile, photos, anchor: look, garments, quality: "pro" }), "pro");
save("demo-back.jpg", back);
console.log("back ok");
