import type { NextFunction, Request, RequestHandler, Response } from "express";

export const ok = <T>(res: Response, data: T, meta?: Record<string, unknown>) =>
  res.json({
    ok: true,
    data,
    ...(meta ? { meta } : {}),
    ts: new Date().toISOString(),
  });

export const asyncHandler =
  (handler: (req: Request, res: Response, next: NextFunction) => Promise<unknown>): RequestHandler =>
  (req, res, next) => {
    void handler(req, res, next).catch(next);
  };

export const getQueryString = (value: unknown): string | undefined => {
  if (typeof value === "string") {
    return value;
  }
  if (Array.isArray(value) && typeof value[0] === "string") {
    return value[0];
  }
  return undefined;
};
