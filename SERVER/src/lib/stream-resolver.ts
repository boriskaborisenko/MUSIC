import ytdl from "@distube/ytdl-core";
import type { Response } from "express";

import { config } from "../config";
import { AppError } from "./app-error";

type AudioFormatLike = {
  itag?: number;
  url?: string;
  mimeType?: string;
  codecs?: string;
  container?: string;
  audioBitrate?: number;
  contentLength?: string;
};

type YtdlCookie = {
  name: string;
  value: string;
  expirationDate?: number;
  domain?: string;
  path?: string;
  secure?: boolean;
  httpOnly?: boolean;
  hostOnly?: boolean;
  sameSite?: string;
};

const isIosFriendlyAudio = (format: AudioFormatLike) => {
  const mime = format.mimeType?.toLowerCase() ?? "";
  const container = format.container?.toLowerCase() ?? "";
  return mime.includes("audio/mp4") || container === "m4a" || container === "mp4";
};

const sortAudioFormats = (formats: AudioFormatLike[]) =>
  [...formats].sort((a, b) => {
    const aScore = (isIosFriendlyAudio(a) ? 1_000 : 0) + (a.audioBitrate ?? 0);
    const bScore = (isIosFriendlyAudio(b) ? 1_000 : 0) + (b.audioBitrate ?? 0);
    return bScore - aScore;
  });

const parseExpiryFromUrl = (url?: string) => {
  if (!url) {
    return null;
  }

  try {
    const parsed = new URL(url);
    const expire = parsed.searchParams.get("expire");
    if (!expire) {
      return null;
    }

    const ms = Number(expire) * 1000;
    return Number.isFinite(ms) ? new Date(ms).toISOString() : null;
  } catch {
    return null;
  }
};

const parseCookieHeader = (rawCookieHeader: string): YtdlCookie[] => {
  const parsed = rawCookieHeader
    .split(";")
    .map((part) => part.trim())
    .filter(Boolean)
    .map<YtdlCookie | null>((part) => {
      const eq = part.indexOf("=");
      if (eq <= 0) {
        return null;
      }
      const name = part.slice(0, eq).trim();
      const value = part.slice(eq + 1).trim();
      if (!name || !value) {
        return null;
      }
      const cookie: YtdlCookie = {
        name,
        value,
        domain: ".youtube.com",
        path: "/",
        secure: true,
      };
      return cookie;
    })
    .filter((cookie): cookie is YtdlCookie => cookie !== null);

  return parsed;
};

const parseConfiguredYtdlCookies = (): YtdlCookie[] => {
  const json = config.playback.ytdlCookiesJson;
  if (json) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(json);
    } catch (error) {
      throw new AppError(
        500,
        "Invalid YTDL_COOKIES_JSON. Expected a JSON array exported from EditThisCookie.",
        "INVALID_YTDL_COOKIES_JSON",
        error instanceof Error ? error.message : undefined,
      );
    }

    if (!Array.isArray(parsed)) {
      throw new AppError(
        500,
        "Invalid YTDL_COOKIES_JSON. Expected a JSON array exported from EditThisCookie.",
        "INVALID_YTDL_COOKIES_JSON",
      );
    }

    const cookies = parsed
      .map((entry) => {
        if (!entry || typeof entry !== "object") {
          return null;
        }
        const name = "name" in entry && typeof entry.name === "string" ? entry.name : null;
        const value = "value" in entry && typeof entry.value === "string" ? entry.value : null;
        if (!name || !value) {
          return null;
        }
        return entry as YtdlCookie;
      })
      .filter((cookie): cookie is YtdlCookie => Boolean(cookie));

    if (cookies.length === 0) {
      throw new AppError(
        500,
        "YTDL_COOKIES_JSON is set but contains no valid cookies.",
        "INVALID_YTDL_COOKIES_JSON",
      );
    }

    return cookies;
  }

  if (config.ytmusic.cookies) {
    return parseCookieHeader(config.ytmusic.cookies);
  }

  return [];
};

const looksLikeYouTubeBotCheck = (error: unknown) => {
  if (!(error instanceof Error)) {
    return false;
  }
  return /sign in to confirm/i.test(error.message) || /not a bot/i.test(error.message);
};

export class StreamResolver {
  private agent: ReturnType<typeof ytdl.createAgent> | null | undefined;

  public isEnabled() {
    return config.playback.resolverEnabled;
  }

  public isProxyEnabled() {
    return config.playback.proxyEnabled;
  }

  private getAgent() {
    if (this.agent !== undefined) {
      return this.agent;
    }

    const cookies = parseConfiguredYtdlCookies();
    this.agent = cookies.length > 0 ? ytdl.createAgent(cookies) : null;
    return this.agent;
  }

  private async getInfo(videoId: string) {
    try {
      const agent = this.getAgent();
      return await ytdl.getInfo(videoId, agent ? { agent } : undefined);
    } catch (error) {
      if (looksLikeYouTubeBotCheck(error)) {
        throw new AppError(
          503,
          "YouTube blocked playback resolution with an anti-bot challenge. Configure YTDL_COOKIES_JSON (or YTMUSIC_COOKIES) on the server and redeploy.",
          "YOUTUBE_BOT_CHECK",
          error instanceof Error ? error.message : undefined,
        );
      }
      throw error;
    }
  }

  async resolve(videoId: string) {
    if (!this.isEnabled()) {
      throw new AppError(501, "Playback resolver is disabled", "PLAYBACK_RESOLVER_DISABLED");
    }

    const info = await this.getInfo(videoId);
    const audioOnly = sortAudioFormats(ytdl.filterFormats(info.formats, "audioonly") as AudioFormatLike[]);

    if (audioOnly.length === 0) {
      throw new AppError(404, "No audio formats available for this video", "NO_AUDIO_FORMATS");
    }

    const selected = audioOnly[0];
    if (!selected.url) {
      throw new AppError(502, "Resolved audio format has no direct URL", "AUDIO_URL_MISSING");
    }

    return {
      videoId,
      title: info.videoDetails.title,
      author: info.videoDetails.author?.name ?? null,
      durationSec: Number(info.videoDetails.lengthSeconds || 0),
      selected: {
        itag: selected.itag ?? null,
        mimeType: selected.mimeType ?? null,
        container: selected.container ?? null,
        codecs: selected.codecs ?? null,
        audioBitrateKbps: selected.audioBitrate ?? null,
        contentLength: selected.contentLength ? Number(selected.contentLength) : null,
        iosPreferred: isIosFriendlyAudio(selected),
      },
      directUrl: selected.url,
      expiresAt: parseExpiryFromUrl(selected.url),
      proxyUrl: this.isProxyEnabled() ? `/api/playback/${videoId}/stream` : null,
      candidates: audioOnly.slice(0, 5).map((format) => ({
        itag: format.itag ?? null,
        mimeType: format.mimeType ?? null,
        container: format.container ?? null,
        codecs: format.codecs ?? null,
        audioBitrateKbps: format.audioBitrate ?? null,
        contentLength: format.contentLength ? Number(format.contentLength) : null,
        iosPreferred: isIosFriendlyAudio(format),
      })),
    };
  }

  async proxy(videoId: string, res: Response) {
    if (!this.isEnabled() || !this.isProxyEnabled()) {
      throw new AppError(501, "Playback proxy is disabled", "PLAYBACK_PROXY_DISABLED");
    }

    const info = await this.getInfo(videoId);
    const audioOnly = sortAudioFormats(ytdl.filterFormats(info.formats, "audioonly") as AudioFormatLike[]);
    const selected = audioOnly[0];

    if (!selected) {
      throw new AppError(404, "No audio formats available for this video", "NO_AUDIO_FORMATS");
    }

    const mime = selected.mimeType?.split(";")[0];
    if (mime) {
      res.setHeader("Content-Type", mime);
    }

    res.setHeader("Accept-Ranges", "bytes");
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("X-Proxy-Source", "ytdl-core");

    const agent = this.getAgent();
    const stream = ytdl(videoId, {
      filter: "audioonly",
      quality: "highestaudio",
      highWaterMark: 1 << 25,
      ...(agent ? { agent } : {}),
    } as any);

    stream.on("error", (error: unknown) => {
      if (!res.headersSent) {
        res.status(502).json({
          ok: false,
          error: {
            code: "PLAYBACK_PROXY_STREAM_ERROR",
            message: error instanceof Error ? error.message : "Unknown stream error",
          },
          ts: new Date().toISOString(),
        });
      } else {
        res.destroy(error instanceof Error ? error : undefined);
      }
    });

    stream.pipe(res);
  }
}

export const streamResolver = new StreamResolver();
