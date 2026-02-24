import cors from "cors";
import express, { type ErrorRequestHandler } from "express";

import { config } from "./config";
import { isAppError } from "./lib/app-error";
import { apiRouter } from "./routes/api";

export const createApp = () => {
  const app = express();

  app.disable("x-powered-by");
  app.use(
    cors({
      origin: config.corsOrigin === "*" ? true : config.corsOrigin,
    }),
  );
  app.use(express.json({ limit: "512kb" }));

  app.use((req, res, next) => {
    const startedAt = Date.now();
    res.on("finish", () => {
      const durationMs = Date.now() - startedAt;
      console.log(`[http] ${req.method} ${req.originalUrl} -> ${res.statusCode} (${durationMs}ms)`);
    });
    next();
  });

  app.get("/health", (_req, res) => {
    res.json({
      ok: true,
      data: {
        status: "ok",
        service: "private-ytmusic-server",
        env: config.nodeEnv,
      },
      ts: new Date().toISOString(),
    });
  });

  app.use("/api", apiRouter);

  app.use((_req, res) => {
    res.status(404).json({
      ok: false,
      error: {
        code: "NOT_FOUND",
        message: "Route not found",
      },
      ts: new Date().toISOString(),
    });
  });

  const errorHandler: ErrorRequestHandler = (error, _req, res, _next) => {
    const appError = isAppError(error) ? error : null;
    const status = appError?.status ?? 500;
    const code = appError?.code ?? "INTERNAL_SERVER_ERROR";
    const message =
      appError?.message ?? (error instanceof Error ? error.message : "Unexpected server error");

    if (status >= 500) {
      console.error("[server:error]", error);
    }

    res.status(status).json({
      ok: false,
      error: {
        code,
        message,
        ...(config.isDev && appError?.details ? { details: appError.details } : {}),
        ...(config.isDev && error instanceof Error && !appError ? { stack: error.stack } : {}),
      },
      ts: new Date().toISOString(),
    });
  };

  app.use(errorHandler);

  return app;
};
