import dotenv from "dotenv";
import { z } from "zod";

dotenv.config();

const boolish = z
  .union([z.boolean(), z.string()])
  .transform((value) => {
    if (typeof value === "boolean") {
      return value;
    }

    return ["1", "true", "yes", "on"].includes(value.toLowerCase());
  });

const envSchema = z.object({
  NODE_ENV: z.string().default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  CORS_ORIGIN: z.string().default("*"),
  YTMUSIC_COOKIES: z.string().optional(),
  YTMUSIC_GL: z.string().default("US"),
  YTMUSIC_HL: z.string().default("en"),
  STREAM_RESOLVER_ENABLED: boolish.default(true),
  STREAM_PROXY_ENABLED: boolish.default(false),
});

const env = envSchema.parse(process.env);

export const config = {
  nodeEnv: env.NODE_ENV,
  isDev: env.NODE_ENV !== "production",
  port: env.PORT,
  corsOrigin: env.CORS_ORIGIN,
  ytmusic: {
    cookies: env.YTMUSIC_COOKIES?.trim() || undefined,
    gl: env.YTMUSIC_GL,
    hl: env.YTMUSIC_HL,
  },
  playback: {
    resolverEnabled: env.STREAM_RESOLVER_ENABLED,
    proxyEnabled: env.STREAM_PROXY_ENABLED,
  },
} as const;
