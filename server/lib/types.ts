// Wire types shared by the API handler, the prompt builders and the tests.
// The iOS client mirrors these in `RenderAPI.swift`; keep the two in sync.

export const BUILDS = [
  "slim",
  "lean",
  "average",
  "athletic",
  "muscular",
  "broad",
  "curvy",
  "plus",
] as const;
export type Build = (typeof BUILDS)[number];

export const PHOTO_ROLES = ["front", "side", "back", "face"] as const;
export type PhotoRole = (typeof PHOTO_ROLES)[number];

export const SLOTS = ["head", "outer", "top", "bottom", "shoes", "accessory"] as const;
export type Slot = (typeof SLOTS)[number];

export const VIEWS = ["front", "threeQuarter", "side", "back"] as const;
export type View = (typeof VIEWS)[number];

export const QUALITIES = ["pro", "fast"] as const;
export type Quality = (typeof QUALITIES)[number];

/** A JPEG/PNG/WebP image, base64 encoded (no data: prefix). */
export interface ImageData {
  mimeType: "image/jpeg" | "image/png" | "image/webp";
  data: string;
}

export interface Profile {
  heightCm: number;
  build: Build;
}

export interface Photo extends ImageData {
  role: PhotoRole;
}

export interface Garment extends ImageData {
  slot: Slot;
}

/**
 * - `avatar`: the user's photos -> a clean "base model" of them in a plain black tee and trousers.
 * - `tryon`: base model + garment screenshots (+ note) -> them wearing the garments, front view.
 * - `view`: an existing try-on result -> the same outfit seen from another angle.
 */
export type RenderRequest =
  | { kind: "avatar"; profile: Profile; photos: Photo[]; quality: Quality }
  | {
      kind: "tryon";
      profile: Profile;
      photos: Photo[];
      base: ImageData;
      garments: Garment[];
      note?: string;
      quality: Quality;
    }
  | {
      kind: "view";
      profile: Profile;
      photos: Photo[];
      anchor: ImageData;
      garments: Garment[];
      note?: string;
      view: Exclude<View, "front">;
      quality: Quality;
    };

export interface RenderResponse {
  image: ImageData;
  model: string;
  ms: number;
}

export type ErrorCode =
  | "bad_request"
  | "unauthorized"
  | "payload_too_large"
  | "blocked"
  | "no_image"
  | "upstream"
  | "rate_limited";

export interface ErrorResponse {
  error: { code: ErrorCode; message: string };
}
