// Local dev server: `npm run dev` -> http://localhost:8787/api/render
// Adapts Node's http module to the same Web Request handler Vercel runs.
import { createServer } from "node:http";
import { handleRender } from "../lib/handler.ts";

const port = Number(process.env.PORT) || 8787;

createServer(async (req, res) => {
  const chunks: Buffer[] = [];
  for await (const c of req) chunks.push(c as Buffer);
  const url = `http://localhost:${port}${req.url}`;
  if (req.url === "/api/health") {
    res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({ ok: true }));
    return;
  }
  if (req.url !== "/api/render") {
    res.writeHead(404).end();
    return;
  }
  const request = new Request(url, {
    method: req.method,
    headers: req.headers as Record<string, string>,
    body: req.method === "POST" ? Buffer.concat(chunks) : undefined,
  });
  const response = await handleRender(request);
  res.writeHead(response.status, Object.fromEntries(response.headers));
  res.end(Buffer.from(await response.arrayBuffer()));
}).listen(port, () => console.log(`clothingonu dev server on http://localhost:${port}`));
