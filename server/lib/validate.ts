import {
  BUILDS,
  PHOTO_ROLES,
  QUALITIES,
  SLOTS,
  VIEWS,
  type ErrorCode,
  type Garment,
  type ImageData,
  type Photo,
  type Profile,
  type RenderRequest,
} from "./types.ts";

export class ApiError extends Error {
  readonly code: ErrorCode;
  readonly status: number;
  constructor(code: ErrorCode, status: number, message: string) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

const MIME = new Set(["image/jpeg", "image/png", "image/webp"]);
/** ~3 MB decoded per image. The client sends ~1024px JPEGs (~250 KB), so this is generous. */
const MAX_IMAGE_B64 = 4_000_000;
const MAX_NOTE = 400;
export const LIMITS = { photos: 4, garments: 6 } as const;

function fail(message: string): never {
  throw new ApiError("bad_request", 400, message);
}

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function oneOf<T extends string>(v: unknown, allowed: readonly T[], field: string): T {
  if (typeof v === "string" && (allowed as readonly string[]).includes(v)) return v as T;
  fail(`${field} must be one of: ${allowed.join(", ")}`);
}

function image(v: unknown, field: string): ImageData {
  if (!isObject(v)) fail(`${field} must be an object`);
  const { mimeType, data } = v;
  if (typeof mimeType !== "string" || !MIME.has(mimeType)) fail(`${field}.mimeType unsupported`);
  if (typeof data !== "string" || data.length < 100) fail(`${field}.data missing`);
  if (data.length > MAX_IMAGE_B64) throw new ApiError("payload_too_large", 413, `${field} is too large`);
  if (data.startsWith("data:")) fail(`${field}.data must be raw base64 without a data: prefix`);
  return { mimeType: mimeType as ImageData["mimeType"], data };
}

function profile(v: unknown): Profile {
  if (!isObject(v)) fail("profile is required");
  const h = v.heightCm;
  if (typeof h !== "number" || !Number.isFinite(h) || h < 90 || h > 250) {
    fail("profile.heightCm must be between 90 and 250");
  }
  return { heightCm: Math.round(h), build: oneOf(v.build, BUILDS, "profile.build") };
}

function photos(v: unknown): Photo[] {
  if (!Array.isArray(v) || v.length === 0) fail("photos must be a non-empty array");
  if (v.length > LIMITS.photos) fail(`at most ${LIMITS.photos} photos`);
  const out = v.map((p, i) => ({ ...image(p, `photos[${i}]`), role: oneOf((p as Photo).role, PHOTO_ROLES, `photos[${i}].role`) }));
  if (!out.some((p) => p.role === "front")) fail("a front photo is required");
  return out;
}

function garments(v: unknown): Garment[] {
  if (!Array.isArray(v) || v.length === 0) fail("garments must be a non-empty array");
  if (v.length > LIMITS.garments) fail(`at most ${LIMITS.garments} garments`);
  return v.map((g, i) => ({ ...image(g, `garments[${i}]`), slot: oneOf((g as Garment).slot, SLOTS, `garments[${i}].slot`) }));
}

function note(v: unknown): string | undefined {
  if (v === undefined || v === null) return undefined;
  if (typeof v !== "string") fail("note must be a string");
  // Collapse whitespace and strip control characters; the note is user text inside our prompt.
  const clean = v.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim();
  if (clean.length > MAX_NOTE) fail(`note must be at most ${MAX_NOTE} characters`);
  return clean || undefined;
}

export function parseRenderRequest(body: unknown): RenderRequest {
  if (!isObject(body)) fail("body must be a JSON object");
  const quality = body.quality === undefined ? "pro" : oneOf(body.quality, QUALITIES, "quality");
  const kind = oneOf(body.kind, ["avatar", "tryon", "view"] as const, "kind");
  const base = { profile: profile(body.profile), photos: photos(body.photos), quality };
  switch (kind) {
    case "avatar":
      return { kind, ...base };
    case "tryon":
      return { kind, ...base, base: image(body.base, "base"), garments: garments(body.garments), note: note(body.note) };
    case "view": {
      const view = oneOf(body.view, VIEWS.filter((x) => x !== "front") as Exclude<(typeof VIEWS)[number], "front">[], "view");
      return { kind, ...base, view, anchor: image(body.anchor, "anchor"), garments: garments(body.garments), note: note(body.note) };
    }
  }
}
