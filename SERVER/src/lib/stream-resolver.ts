import { execFile } from "node:child_process";
import { Readable } from "node:stream";
import { promisify } from "node:util";
import ytdl from "@distube/ytdl-core";
import type { Request, Response } from "express";

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

type ResolvedPlayback = {
  videoId: string;
  title: string | null;
  author: string | null;
  durationSec: number;
  selected: {
    itag: number | null;
    mimeType: string | null;
    container: string | null;
    codecs: string | null;
    audioBitrateKbps: number | null;
    contentLength: number | null;
    iosPreferred: boolean;
  };
  directUrl: string;
  expiresAt: string | null;
  proxyUrl: string | null;
  candidates: Array<{
    itag: number | null;
    mimeType: string | null;
    container: string | null;
    codecs: string | null;
    audioBitrateKbps: number | null;
    contentLength: number | null;
    iosPreferred: boolean;
  }>;
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

const execFileAsync = promisify(execFile);

export class StreamResolver {
  private agent: ReturnType<typeof ytdl.createAgent> | null | undefined;
  private resolutionCache = new Map<
    string,
    {
      value: ResolvedPlayback;
      expiresAtMs: number;
    }
  >();

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

  private getCachedResolution(videoId: string): ResolvedPlayback | null {
    const entry = this.resolutionCache.get(videoId);
    if (!entry) {
      return null;
    }

    if (Date.now() >= entry.expiresAtMs) {
      this.resolutionCache.delete(videoId);
      return null;
    }

    return entry.value;
  }

  private setCachedResolution(resolution: ResolvedPlayback) {
    const parsedExpiry = resolution.expiresAt ? Date.parse(resolution.expiresAt) : NaN;
    const fallbackTtlMs = 3 * 60 * 1000;
    const rawExpiryMs = Number.isFinite(parsedExpiry) ? parsedExpiry : Date.now() + fallbackTtlMs;

    // Keep a small safety margin so we don't hand out URLs close to expiration.
    const expiresAtMs = Math.max(Date.now() + 5_000, rawExpiryMs - 30_000);
    this.resolutionCache.set(resolution.videoId, { value: resolution, expiresAtMs });
  }

  private clearCachedResolution(videoId: string) {
    this.resolutionCache.delete(videoId);
  }

  private updateCachedResolutionDirectUrl(videoId: string, directUrl: string) {
    const cached = this.getCachedResolution(videoId);
    if (!cached) {
      return;
    }

    const updated: ResolvedPlayback = {
      ...cached,
      directUrl,
      expiresAt: parseExpiryFromUrl(directUrl),
    };
    this.setCachedResolution(updated);
  }

  private async resolveDirectUrlWithYtDlp(videoId: string): Promise<string | null> {
    try {
      const { stdout } = await execFileAsync(
        "yt-dlp",
        [
          "-g",
          "--no-playlist",
          "--no-warnings",
          "-f",
          "140/bestaudio[ext=m4a]/bestaudio",
          `https://www.youtube.com/watch?v=${videoId}`,
        ],
        {
          timeout: 20_000,
          maxBuffer: 1024 * 1024,
        },
      );

      const url = stdout
        .split(/\r?\n/g)
        .map((line) => line.trim())
        .find((line) => /^https?:\/\//i.test(line));

      return url ?? null;
    } catch {
      return null;
    }
  }

  async resolve(videoId: string): Promise<ResolvedPlayback> {
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

    const resolved: ResolvedPlayback = {
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

    this.setCachedResolution(resolved);
    return resolved;
  }

  async proxy(videoId: string, req: Request, res: Response) {
    if (!this.isEnabled() || !this.isProxyEnabled()) {
      throw new AppError(501, "Playback proxy is disabled", "PLAYBACK_PROXY_DISABLED");
    }

    let resolved = this.getCachedResolution(videoId) ?? (await this.resolve(videoId));
    let selected = resolved.selected;

    const mime = selected.mimeType?.split(";")[0];
    if (mime) {
      res.setHeader("Content-Type", mime);
    }

    const totalLength =
      selected.contentLength && Number.isFinite(selected.contentLength)
        ? selected.contentLength
        : null;

    const rangeHeader = typeof req.headers.range === "string" ? req.headers.range : null;
    let byteRange: { start?: number; end?: number } | null = null;

    if (rangeHeader && totalLength) {
      const match = /^bytes=(\d*)-(\d*)$/i.exec(rangeHeader.trim());
      if (!match) {
        res.setHeader("Content-Range", `bytes */${totalLength}`);
        throw new AppError(416, "Invalid Range header", "INVALID_RANGE_HEADER");
      }

      const [, rawStart, rawEnd] = match;
      if (!rawStart && !rawEnd) {
        res.setHeader("Content-Range", `bytes */${totalLength}`);
        throw new AppError(416, "Invalid Range header", "INVALID_RANGE_HEADER");
      }

      let start = rawStart ? Number(rawStart) : NaN;
      let end = rawEnd ? Number(rawEnd) : NaN;

      if (!rawStart && rawEnd) {
        const suffixLength = Number(rawEnd);
        if (!Number.isFinite(suffixLength) || suffixLength <= 0) {
          res.setHeader("Content-Range", `bytes */${totalLength}`);
          throw new AppError(416, "Invalid Range header", "INVALID_RANGE_HEADER");
        }
        start = Math.max(totalLength - suffixLength, 0);
        end = totalLength - 1;
      } else {
        if (!Number.isFinite(start) || start < 0) {
          res.setHeader("Content-Range", `bytes */${totalLength}`);
          throw new AppError(416, "Invalid Range header", "INVALID_RANGE_HEADER");
        }
        if (!rawEnd) {
          end = totalLength - 1;
        }
      }

      if (!Number.isFinite(end) || end < start || start >= totalLength) {
        res.setHeader("Content-Range", `bytes */${totalLength}`);
        throw new AppError(416, "Requested range not satisfiable", "RANGE_NOT_SATISFIABLE");
      }

      end = Math.min(end, totalLength - 1);
      byteRange = { start, end };
      res.status(206);
      res.setHeader("Content-Range", `bytes ${start}-${end}/${totalLength}`);
      res.setHeader("Content-Length", String(end - start + 1));
    } else if (totalLength) {
      res.setHeader("Content-Length", String(totalLength));
    }

    res.setHeader("Accept-Ranges", "bytes");
    res.setHeader("Cache-Control", "no-store");

    const upstreamRange =
      byteRange && typeof byteRange.start === "number" && typeof byteRange.end === "number"
        ? `bytes=${byteRange.start}-${byteRange.end}`
        : rangeHeader ?? undefined;

    const fetchUpstream = async (directUrl: string) => {
      try {
        return await fetch(directUrl, {
          headers: upstreamRange ? { Range: upstreamRange } : undefined,
        });
      } catch (error) {
        throw new AppError(
          502,
          error instanceof Error ? error.message : "Failed to fetch upstream audio stream",
          "PLAYBACK_PROXY_STREAM_ERROR",
        );
      }
    };

    let upstreamSource = "ytdl-core";
    let upstream = await fetchUpstream(resolved.directUrl);
    if (upstream.status === 403) {
      // Refresh the signed URL once; repeated /stream chunk requests from AVPlayer can race flaky URL generation.
      this.clearCachedResolution(videoId);
      resolved = await this.resolve(videoId);
      selected = resolved.selected;
      upstream = await fetchUpstream(resolved.directUrl);
    }

    if (upstream.status === 403) {
      const ytDlpUrl = await this.resolveDirectUrlWithYtDlp(videoId);
      if (ytDlpUrl) {
        upstream = await fetchUpstream(ytDlpUrl);
        if ([200, 206].includes(upstream.status)) {
          upstreamSource = "yt-dlp";
          this.updateCachedResolutionDirectUrl(videoId, ytDlpUrl);
        }
      }
    }

    if (![200, 206].includes(upstream.status)) {
      throw new AppError(502, `Status code: ${upstream.status}`, "PLAYBACK_PROXY_STREAM_ERROR");
    }

    res.status(upstream.status);
    res.setHeader("X-Proxy-Source", upstreamSource);

    const upstreamContentType = upstream.headers.get("content-type");
    if (upstreamContentType) {
      res.setHeader("Content-Type", upstreamContentType);
    }
    const upstreamContentLength = upstream.headers.get("content-length");
    if (upstreamContentLength) {
      res.setHeader("Content-Length", upstreamContentLength);
    }
    const upstreamContentRange = upstream.headers.get("content-range");
    if (upstreamContentRange) {
      res.setHeader("Content-Range", upstreamContentRange);
    }
    const upstreamAcceptRanges = upstream.headers.get("accept-ranges");
    if (upstreamAcceptRanges) {
      res.setHeader("Accept-Ranges", upstreamAcceptRanges);
    }

    if (!upstream.body) {
      throw new AppError(502, "Upstream audio stream has no body", "PLAYBACK_PROXY_STREAM_ERROR");
    }

    const bodyStream = Readable.fromWeb(upstream.body as any);
    bodyStream.on("error", (error: unknown) => {
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

    bodyStream.pipe(res);
  }
}

export const streamResolver = new StreamResolver();
