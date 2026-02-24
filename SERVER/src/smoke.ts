import type { AddressInfo } from "node:net";

import { createApp } from "./app";

type ApiResponse = {
  ok: boolean;
  data?: unknown;
  error?: { code?: string; message?: string };
  meta?: Record<string, unknown>;
};

const preview = (value: unknown) => JSON.stringify(value, null, 2).slice(0, 320);

const run = async () => {
  const app = createApp();
  const server = app.listen(0, "127.0.0.1");

  await new Promise<void>((resolve, reject) => {
    server.once("listening", () => resolve());
    server.once("error", reject);
  });

  const { port } = server.address() as AddressInfo;
  const base = `http://127.0.0.1:${port}`;

  const hit = async (path: string) => {
    const response = await fetch(`${base}${path}`);
    const json = (await response.json()) as ApiResponse;
    return { status: response.status, json };
  };

  try {
    const checks: Array<{ path: string; required: boolean }> = [
      { path: "/health", required: true },
      { path: "/api/bootstrap", required: true },
      { path: "/api/search?q=daft%20punk&type=songs", required: true },
      { path: "/api/playback/dQw4w9WgXcQ/resolve", required: false },
    ];

    for (const check of checks) {
      try {
        const result = await hit(check.path);
        console.log(`\n[SMOKE] ${check.path}`);
        console.log(`status=${result.status} ok=${result.json.ok}`);
        if (result.json.ok) {
          console.log(`payload=${preview(result.json.data)}`);
        } else {
          console.log(`error=${preview(result.json.error)}`);
          if (check.required) {
            process.exitCode = 1;
          }
        }
      } catch (error) {
        console.log(`\n[SMOKE] ${check.path}`);
        console.log(`network/error=${error instanceof Error ? error.message : String(error)}`);
        if (check.required) {
          process.exitCode = 1;
        }
      }
    }
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((err) => (err ? reject(err) : resolve()));
    });
  }
};

void run().catch((error) => {
  console.error("[SMOKE] fatal", error);
  process.exit(1);
});
