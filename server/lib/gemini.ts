// Thin Gemini image client: one generateContent call, typed failures, bounded retries.

import { ApiError } from "./validate.js";
import type { ImageData, Quality } from "./types.js";
import type { Part } from "./prompts.js";

const ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models";
const BLOCK_REASONS = new Set(["SAFETY", "PROHIBITED_CONTENT", "IMAGE_SAFETY", "BLOCKLIST", "SPII", "IMAGE_PROHIBITED_CONTENT", "RECITATION"]);

export interface ModelConfig {
  apiKey: string;
  pro: string;
  fast: string;
  timeoutMs: number;
  deadlineMs: number;
}

export function configFromEnv(env: NodeJS.ProcessEnv = process.env): ModelConfig {
  const apiKey = env.GEMINI_API_KEY;
  if (!apiKey) throw new Error("GEMINI_API_KEY is not set");
  return {
    apiKey,
    pro: env.MODEL_PRO || "gemini-3-pro-image",
    fast: env.MODEL_FAST || "gemini-nano-banana-2.1",
    timeoutMs: Number(env.MODEL_TIMEOUT_MS) || 90_000,
    // Total budget across retries + fallback. The iOS client waits 200 s, so finish well before.
    deadlineMs: Number(env.MODEL_DEADLINE_MS) || 170_000,
  };
}

interface GeminiResponse {
  candidates?: {
    finishReason?: string;
    content?: { parts?: { text?: string; thought?: boolean; inlineData?: { mimeType: string; data: string } }[] };
  }[];
  promptFeedback?: { blockReason?: string };
  error?: { code: number; message: string; status: string };
}

/** Extract the generated image, or throw an ApiError explaining why there isn't one. */
export function extractImage(body: GeminiResponse): ImageData {
  if (body.promptFeedback?.blockReason) {
    throw new ApiError("blocked", 422, `The request was blocked (${body.promptFeedback.blockReason}). Try a different photo or garment.`);
  }
  const cand = body.candidates?.[0];
  const parts = cand?.content?.parts ?? [];
  // Thinking models may emit draft "thought" images first; the answer is the last non-thought image.
  const images = parts.filter((p) => p.inlineData && !p.thought);
  const found = images.at(-1)?.inlineData;
  if (found) return { mimeType: found.mimeType as ImageData["mimeType"], data: found.data };
  if (cand?.finishReason && BLOCK_REASONS.has(cand.finishReason)) {
    throw new ApiError("blocked", 422, `The image was blocked by the model's safety filter (${cand.finishReason}). Try a different photo or garment.`);
  }
  throw new ApiError("no_image", 502, "The model didn't return an image. Please try again.");
}

async function callOnce(cfg: ModelConfig, model: string, parts: Part[], fetchImpl: typeof fetch, timeoutMs: number): Promise<ImageData> {
  const res = await fetchImpl(`${ENDPOINT}/${model}:generateContent`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-goog-api-key": cfg.apiKey },
    body: JSON.stringify({
      contents: [{ role: "user", parts }],
      generationConfig: {
        responseModalities: ["IMAGE"],
        imageConfig: { aspectRatio: "3:4", imageSize: "2K" },
      },
    }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const body = (await res.json().catch(() => ({}))) as GeminiResponse;
  if (!res.ok) {
    const msg = body.error?.message ?? `HTTP ${res.status}`;
    if (res.status === 429) throw new ApiError("rate_limited", 429, "The try-on engine is busy. Try again in a moment.");
    // Never show provider messages to users: they can be about our billing/quota, not their request.
    console.error(JSON.stringify({ upstream: res.status, model, reason: body.error?.status ?? "unknown" }));
    void msg;
    if (res.status === 400) throw new ApiError("bad_request", 400, "The try-on engine couldn't read that request. Try different images.");
    throw new ApiError("upstream", 503, "The try-on engine is unavailable right now. Please try again in a few minutes.");
  }
  return extractImage(body);
}

const retryable = (e: unknown) => e instanceof ApiError && (e.code === "upstream" || e.code === "no_image" || e.code === "rate_limited");

/**
 * Generate one image. Pro gets one retry; if it still fails for a transient reason we fall
 * back to the fast model so the user gets *a* result rather than an error.
 * Safety blocks and bad requests are never retried: retrying them only burns money.
 */
export async function generateImage(
  cfg: ModelConfig,
  parts: Part[],
  quality: Quality,
  fetchImpl: typeof fetch = fetch,
): Promise<{ image: ImageData; model: string }> {
  const plan = quality === "pro" ? [cfg.pro, cfg.pro, cfg.fast] : [cfg.fast, cfg.fast];
  const deadline = Date.now() + cfg.deadlineMs;
  let last: unknown = new ApiError("upstream", 504, "The model took too long.");
  for (const model of plan) {
    const remaining = deadline - Date.now();
    // Not worth starting an attempt that can't finish; a render needs ~20 s.
    if (remaining < 25_000) break;
    try {
      return { image: await callOnce(cfg, model, parts, fetchImpl, Math.min(cfg.timeoutMs, remaining)), model };
    } catch (e) {
      last = e instanceof Error && e.name === "TimeoutError" ? new ApiError("upstream", 504, "The model took too long.") : e;
      if (!retryable(last)) break;
    }
  }
  throw last;
}
