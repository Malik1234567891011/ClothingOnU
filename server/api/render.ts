import { handleRender } from "../lib/handler.js";

// Pro renders take 20-60 s; leave room for one retry plus the fast-model fallback.
export const config = { maxDuration: 300 };

export function POST(request: Request): Promise<Response> {
  return handleRender(request);
}
