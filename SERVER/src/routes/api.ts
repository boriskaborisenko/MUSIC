import { Router } from "express";

import { config } from "../config";
import { AppError } from "../lib/app-error";
import { asyncHandler, getQueryString, ok } from "../lib/http";
import { streamResolver } from "../lib/stream-resolver";
import { type SearchType, ytmusicService } from "../lib/ytmusic-service";

const router = Router();

const searchTypes = new Set<SearchType>(["all", "songs", "videos", "artists", "albums", "playlists"]);

const requireQuery = (name: string, rawValue: unknown) => {
  const value = getQueryString(rawValue)?.trim();
  if (!value) {
    throw new AppError(400, `Missing query parameter: ${name}`, "MISSING_QUERY_PARAM");
  }
  return value;
};

const requireParam = (name: string, rawValue: unknown) => {
  if (typeof rawValue !== "string" || rawValue.trim() === "") {
    throw new AppError(400, `Missing path parameter: ${name}`, "MISSING_PATH_PARAM");
  }
  return rawValue.trim();
};

router.get(
  "/bootstrap",
  asyncHandler(async (_req, res) => {
    ok(res, {
      name: "private-ytmusic-server",
      mode: config.nodeEnv,
      capabilities: {
        metadata: true,
        lyrics: true,
        homeSections: true,
        playbackResolver: streamResolver.isEnabled(),
        playbackProxy: streamResolver.isProxyEnabled(),
      },
      region: {
        gl: config.ytmusic.gl,
        hl: config.ytmusic.hl,
      },
    });
  }),
);

router.get(
  "/search/suggestions",
  asyncHandler(async (req, res) => {
    const q = requireQuery("q", req.query.q);
    const suggestions = await ytmusicService.getSearchSuggestions(q);
    ok(res, suggestions, { query: q });
  }),
);

router.get(
  "/search",
  asyncHandler(async (req, res) => {
    const q = requireQuery("q", req.query.q);
    const requestedType = (getQueryString(req.query.type) ?? "all").trim().toLowerCase() as SearchType;
    const type = searchTypes.has(requestedType) ? requestedType : "all";
    const results = await ytmusicService.search(q, type);
    ok(res, results, { query: q, type, count: Array.isArray(results) ? results.length : undefined });
  }),
);

router.get(
  "/home",
  asyncHandler(async (_req, res) => {
    const sections = await ytmusicService.getHomeSections();
    ok(res, sections, { count: sections.length });
  }),
);

router.get(
  "/songs/:videoId/up-next",
  asyncHandler(async (req, res) => {
    const videoId = requireParam("videoId", req.params.videoId);
    const upNext = await ytmusicService.getUpNexts(videoId);
    ok(res, upNext, { videoId, count: upNext.length });
  }),
);

router.get(
  "/songs/:videoId/lyrics",
  asyncHandler(async (req, res) => {
    const videoId = requireParam("videoId", req.params.videoId);
    const lyrics = await ytmusicService.getLyrics(videoId);
    ok(res, lyrics, { videoId, hasLyrics: Boolean(lyrics && lyrics.length) });
  }),
);

router.get(
  "/songs/:videoId",
  asyncHandler(async (req, res) => {
    const videoId = requireParam("videoId", req.params.videoId);
    const song = await ytmusicService.getSong(videoId);
    ok(res, song, { videoId });
  }),
);

router.get(
  "/videos/:videoId",
  asyncHandler(async (req, res) => {
    const videoId = requireParam("videoId", req.params.videoId);
    const video = await ytmusicService.getVideo(videoId);
    ok(res, video, { videoId });
  }),
);

router.get(
  "/artists/:artistId/songs",
  asyncHandler(async (req, res) => {
    const artistId = requireParam("artistId", req.params.artistId);
    const songs = await ytmusicService.getArtistSongs(artistId);
    ok(res, songs, { artistId, count: songs.length });
  }),
);

router.get(
  "/artists/:artistId/albums",
  asyncHandler(async (req, res) => {
    const artistId = requireParam("artistId", req.params.artistId);
    const albums = await ytmusicService.getArtistAlbums(artistId);
    ok(res, albums, { artistId, count: albums.length });
  }),
);

router.get(
  "/artists/:artistId",
  asyncHandler(async (req, res) => {
    const artistId = requireParam("artistId", req.params.artistId);
    const artist = await ytmusicService.getArtist(artistId);
    ok(res, artist, { artistId });
  }),
);

router.get(
  "/albums/:albumId",
  asyncHandler(async (req, res) => {
    const albumId = requireParam("albumId", req.params.albumId);
    const album = await ytmusicService.getAlbum(albumId);
    ok(res, album, { albumId });
  }),
);

router.get(
  "/playlists/:playlistId/videos",
  asyncHandler(async (req, res) => {
    const playlistId = requireParam("playlistId", req.params.playlistId);
    const videos = await ytmusicService.getPlaylistVideos(playlistId);
    ok(res, videos, { playlistId, count: videos.length });
  }),
);

router.get(
  "/playlists/:playlistId",
  asyncHandler(async (req, res) => {
    const playlistId = requireParam("playlistId", req.params.playlistId);
    const playlist = await ytmusicService.getPlaylist(playlistId);
    ok(res, playlist, { playlistId });
  }),
);

router.get(
  "/playback/:videoId/resolve",
  asyncHandler(async (req, res) => {
    const videoId = requireParam("videoId", req.params.videoId);
    const playback = await streamResolver.resolve(videoId);
    ok(res, playback, { videoId });
  }),
);

router.get(
  "/playback/:videoId/stream",
  asyncHandler(async (req, res) => {
    const videoId = requireParam("videoId", req.params.videoId);
    await streamResolver.proxy(videoId, req, res);
  }),
);

export const apiRouter = router;
