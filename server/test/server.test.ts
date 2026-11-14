import { test } from "node:test";
import assert from "node:assert/strict";
import { parseRenderRequest, ApiError } from "../lib/validate.js";
import { buildParts, type Part } from "../lib/prompts.js";
import { extractImage, generateImage, type ModelConfig } from "../lib/gemini.js";
import { handleRender } from "../lib/handler.js";

const B64 = "A".repeat(200);
const jpg = { mimeType: "image/jpeg", data: B64 };
const profile = { heightCm: 180, build: "athletic" };
const cfg: ModelConfig = { apiKey: "k", pro: "pro-model", fast: "fast-model", timeoutMs: 1000 };

const textOf = (parts: Part[]) => parts.map((p) => ("text" in p ? p.text : "[IMG]")).join("\n");
const imageCount = (parts: Part[]) => parts.filter((p) => "inlineData" in p).length;

test("avatar request parses with defaults", () => {
  const r = parseRenderRequest({ kind: "avatar", profile, photos: [{ ...jpg, role: "front" }] });
  assert.equal(r.kind, "avatar");
  assert.equal(r.quality, "pro");
});

test("rejects missing front photo, bad build, bad height, data: prefixes", () => {
  const bad = [
    { kind: "avatar", profile, photos: [{ ...jpg, role: "side" }] },
    { kind: "avatar", profile: { heightCm: 180, build: "chunky" }, photos: [{ ...jpg, role: "front" }] },
    { kind: "avatar", profile: { heightCm: 20, build: "slim" }, photos: [{ ...jpg, role: "front" }] },
    { kind: "avatar", profile, photos: [{ mimeType: "image/jpeg", data: "data:" + B64, role: "front" }] },
    { kind: "tryon", profile, photos: [{ ...jpg, role: "front" }], base: jpg, garments: [] },
    { kind: "view", profile, photos: [{ ...jpg, role: "front" }], anchor: jpg, garments: [{ ...jpg, slot: "top" }], view: "front" },
  ];
  for (const b of bad) assert.throws(() => parseRenderRequest(b), ApiError, JSON.stringify(b).slice(0, 80));
});

test("note is sanitised and length-limited", () => {
  const r = parseRenderRequest({
    kind: "tryon", profile, photos: [{ ...jpg, role: "front" }], base: jpg,
    garments: [{ ...jpg, slot: "outer" }], note: "  leave it\n\nunzipped\u0007 ",
  });
  assert.equal(r.kind === "tryon" && r.note, "leave it unzipped");
  assert.throws(() => parseRenderRequest({ ...r, note: "x".repeat(401) }), ApiError);
});

test("try-on prompt: base first, every garment labelled, layering kept, note fenced", () => {
  const r = parseRenderRequest({
    kind: "tryon", profile, base: jpg, note: "hood up",
    photos: [{ ...jpg, role: "front" }, { ...jpg, role: "side" }, { ...jpg, role: "face" }],
    garments: [{ ...jpg, slot: "outer" }, { ...jpg, slot: "bottom" }],
  });
  const parts = buildParts(r);
  const t = textOf(parts);
  // base + front + face (side is not needed for a front render) + 2 garments
  assert.equal(imageCount(parts), 5);
  assert.match(t, /BASE PHOTO/);
  assert.match(t, /GARMENT 1: outer layer/);
  assert.match(t, /GARMENT 2: bottoms/);
  assert.match(t, /Keep the plain grey t-shirt from the base photo under the outer layer/);
  assert.match(t, /Keep the white sneakers/);
  assert.doesNotMatch(t, /Keep the black trousers/);
  assert.match(t, /<<hood up>>/);
  assert.match(t, /Do not slim/);
  assert.match(t, /180 cm \(5'11"\)/);
});

test("view prompt names the angle and keeps the outfit", () => {
  const r = parseRenderRequest({
    kind: "view", profile, view: "back", anchor: jpg,
    photos: [{ ...jpg, role: "front" }, { ...jpg, role: "back" }],
    garments: [{ ...jpg, slot: "top" }],
  });
  const t = textOf(buildParts(r));
  assert.match(t, /from directly behind/);
  assert.match(t, /FRONT PHOTO/);
  assert.match(t, /back view/);
});

test("person references are ordered front, face, side, back", () => {
  const r = parseRenderRequest({
    kind: "avatar", profile,
    photos: [{ ...jpg, role: "back" }, { ...jpg, role: "side" }, { ...jpg, role: "face" }, { ...jpg, role: "front" }],
  });
  const refs = textOf(buildParts(r)).match(/PERSON REFERENCE \d \(([a-z -]+)\)/g);
  assert.deepEqual(refs, [
    "PERSON REFERENCE 1 (front view)", "PERSON REFERENCE 2 (face close-up)",
    "PERSON REFERENCE 3 (side view)", "PERSON REFERENCE 4 (back view)",
  ]);
});

test("extractImage takes the last non-thought image and classifies blocks", () => {
  const img = extractImage({
    candidates: [{ content: { parts: [
      { inlineData: { mimeType: "image/png", data: "draft" }, thought: true },
      { inlineData: { mimeType: "image/jpeg", data: "final" } },
    ] } }],
  });
  assert.equal(img.data, "final");
  assert.throws(() => extractImage({ promptFeedback: { blockReason: "SAFETY" } }), (e: ApiError) => e.code === "blocked");
  assert.throws(() => extractImage({ candidates: [{ finishReason: "IMAGE_SAFETY", content: { parts: [] } }] }), (e: ApiError) => e.code === "blocked");
  assert.throws(() => extractImage({ candidates: [{ finishReason: "STOP", content: { parts: [{ text: "I can't" }] } }] }), (e: ApiError) => e.code === "no_image");
});

function fakeFetch(script: (model: string) => { status: number; body: unknown }) {
  const calls: string[] = [];
  const impl = (async (url: string | URL) => {
    const model = String(url).split("/models/")[1]!.split(":")[0]!;
    calls.push(model);
    const { status, body } = script(model);
    return new Response(JSON.stringify(body), { status });
  }) as typeof fetch;
  return { impl, calls };
}
const ok = { candidates: [{ content: { parts: [{ inlineData: { mimeType: "image/jpeg", data: "IMG" } }] } }] };

test("pro retries once, then falls back to fast", async () => {
  const f = fakeFetch((m) => (m === "pro-model" ? { status: 503, body: { error: { message: "overloaded" } } } : { status: 200, body: ok }));
  const out = await generateImage(cfg, [], "pro", f.impl);
  assert.deepEqual(f.calls, ["pro-model", "pro-model", "fast-model"]);
  assert.equal(out.model, "fast-model");
});

test("safety blocks are not retried", async () => {
  const f = fakeFetch(() => ({ status: 200, body: { promptFeedback: { blockReason: "SAFETY" } } }));
  await assert.rejects(generateImage(cfg, [], "pro", f.impl), (e: ApiError) => e.code === "blocked");
  assert.deepEqual(f.calls, ["pro-model"]);
});

test("handler enforces the app token and returns typed errors", async () => {
  const req = (headers: Record<string, string>, body: unknown) =>
    new Request("http://x/api/render", { method: "POST", headers, body: JSON.stringify(body) });
  const quiet = { log: () => {}, config: cfg, appToken: "secret" };

  const r401 = await handleRender(req({}, {}), quiet);
  assert.equal(r401.status, 401);

  const r400 = await handleRender(req({ "x-app-token": "secret" }, { kind: "nope" }), quiet);
  assert.equal(r400.status, 400);
  assert.equal(((await r400.json()) as { error: { code: string } }).error.code, "bad_request");

  const f = fakeFetch(() => ({ status: 200, body: ok }));
  const r200 = await handleRender(
    req({ "x-app-token": "secret" }, { kind: "avatar", profile, photos: [{ ...jpg, role: "front" }] }),
    { ...quiet, fetchImpl: f.impl },
  );
  assert.equal(r200.status, 200);
  const body = (await r200.json()) as { image: { data: string }; model: string };
  assert.equal(body.image.data, "IMG");
  assert.equal(body.model, "pro-model");
});
