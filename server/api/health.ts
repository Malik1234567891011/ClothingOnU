export function GET(): Response {
  return Response.json({ ok: true, service: "clothingonu", configured: Boolean(process.env.GEMINI_API_KEY) });
}
