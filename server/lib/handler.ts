// Framework-free request handler (Web Request -> Response) so the same code runs on
// Vercel and in the local dev server.

import { timingSafeEqual } from "node:crypto";
import { configFromEnv, generateImage, type ModelConfig } from "./gemini.js";
import { buildParts } from "./prompts.js";
import { ApiError, parseRenderRequest } from "./validate.js";
import type { ErrorResponse, RenderResponse } from "./types.js";

/** Vercel rejects bodies over 4.5 MB; fail with a clear message before that. */
const MAX_BODY_BYTES = 4_400_000;

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

const errorResponse = (e: ApiError) => json(e.status, { error: { code: e.code, message: e.message } } satisfies ErrorResponse);

function authorized(req: Request, token: string | undefined): boolean {
  if (!token) return true; // auth disabled (local dev)
  const got = Buffer.from(req.headers.get("x-app-token") ?? "");
  const want = Buffer.from(token);
  return got.length === want.length && timingSafeEqual(got, want);
}

export interface Deps {
  config?: ModelConfig;
  appToken?: string;
  fetchImpl?: typeof fetch;
  log?: (line: Record<string, unknown>) => void;
}

export async function handleRender(req: Request, deps: Deps = {}): Promise<Response> {
  const started = Date.now();
  const log = deps.log ?? ((l) => console.log(JSON.stringify(l)));
  try {
    if (req.method !== "POST") return json(405, { error: { code: "bad_request", message: "POST only" } });
    if (!authorized(req, deps.appToken ?? process.env.APP_TOKEN)) throw new ApiError("unauthorized", 401, "Missing or wrong app token.");

    const declared = Number(req.headers.get("content-length") ?? 0);
    if (declared > MAX_BODY_BYTES) throw new ApiError("payload_too_large", 413, "Request too large; send smaller images.");
    const raw = await req.text();
    if (raw.length > MAX_BODY_BYTES) throw new ApiError("payload_too_large", 413, "Request too large; send smaller images.");

    let body: unknown;
    try {
      body = JSON.parse(raw);
    } catch {
      throw new ApiError("bad_request", 400, "Body is not valid JSON.");
    }
    const request = parseRenderRequest(body);
    const config = deps.config ?? configFromEnv();
    const { image, model } = await generateImage(config, buildParts(request), request.quality, deps.fetchImpl);

    const ms = Date.now() - started;
    // Never log images, notes or anything personal; shape and timing only.
    log({ ok: true, kind: request.kind, model, ms, garments: "garments" in request ? request.garments.length : 0, bytesIn: raw.length });
    return json(200, { image, model, ms } satisfies RenderResponse);
  } catch (e) {
    const err = e instanceof ApiError ? e : new ApiError("upstream", 500, "Unexpected server error.");
    log({ ok: false, code: err.code, status: err.status, ms: Date.now() - started, detail: e instanceof Error ? e.message.slice(0, 300) : String(e) });
    return errorResponse(err);
  }
}
