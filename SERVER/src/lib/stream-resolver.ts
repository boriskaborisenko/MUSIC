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

export class StreamResolver {
  public isEnabled() {
    return config.playback.resolverEnabled;
  }

  public isProxyEnabled() {
    return config.playback.proxyEnabled;
  }

  async resolve(videoId: string) {
    if (!this.isEnabled()) {
      throw new AppError(501, "Playback resolver is disabled", "PLAYBACK_RESOLVER_DISABLED");
    }

    const info = await ytdl.getInfo(videoId);
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

    const info = await ytdl.getInfo(videoId);
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

    const stream = ytdl(videoId, {
      filter: "audioonly",
      quality: "highestaudio",
      highWaterMark: 1 << 25,
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
