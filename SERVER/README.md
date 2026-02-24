# Private YTMusic Server (MVP)

Backend for a native iOS client (Apple Music-like UI) using:

- `ytmusic-api` for metadata (search, albums, artists, playlists, lyrics)
- `@distube/ytdl-core` for playback URL resolution (optional but enabled by default)
- `Express + TypeScript`

## Quick Start

```bash
npm install
cp .env.example .env
npm run dev
```

Server starts on `http://localhost:3000` by default.

## API (MVP)

- `GET /health`
- `GET /api/bootstrap`
- `GET /api/search?q=...&type=all|songs|videos|artists|albums|playlists`
- `GET /api/search/suggestions?q=...`
- `GET /api/home`
- `GET /api/songs/:videoId`
- `GET /api/songs/:videoId/up-next`
- `GET /api/songs/:videoId/lyrics`
- `GET /api/videos/:videoId`
- `GET /api/artists/:artistId`
- `GET /api/artists/:artistId/songs`
- `GET /api/artists/:artistId/albums`
- `GET /api/albums/:albumId`
- `GET /api/playlists/:playlistId`
- `GET /api/playlists/:playlistId/videos`
- `GET /api/playback/:videoId/resolve`
- `GET /api/playback/:videoId/stream` (optional proxy fallback)

## Smoke Test Examples

```bash
curl http://localhost:3000/health
curl "http://localhost:3000/api/search?q=daft%20punk&type=songs"
curl "http://localhost:3000/api/playback/dQw4w9WgXcQ/resolve"
```

## Notes for iOS Client

- Prefer `.../resolve` right before playback and feed `directUrl` to `AVPlayer`.
- `directUrl` can expire; request a fresh one when starting/retrying playback.
- Use `/stream` only as fallback (proxying costs server bandwidth and can increase latency).

## Render / YouTube Anti-Bot Notes

If playback resolve fails with a message like `Sign in to confirm you're not a bot`:

- Set `YTDL_COOKIES_JSON` in Render to a one-line JSON array exported from EditThisCookie (YouTube cookies)
- Optionally also set `YTMUSIC_COOKIES` (raw `Cookie:` header string) for `ytmusic-api`
- Redeploy and retry `/api/playback/:videoId/resolve`

## Docker (with `yt-dlp`) for Render

The repo includes `SERVER/Dockerfile` that bundles:

- Node.js 20
- your compiled server (`dist/`)
- `yt-dlp` (used as a fallback when `@distube/ytdl-core` fails on YouTube changes)

### Build locally (optional)

```bash
cd SERVER
docker build -t private-ytmusic-server .
docker run --rm -p 3000:3000 --env-file .env private-ytmusic-server
```

### Render Docker Service (Dashboard)

Create a new **Web Service** in Render and choose the repo, then set:

- `Root Directory`: `SERVER`
- `Runtime`: `Docker`
- `Dockerfile Path`: `./Dockerfile` (or leave default if Render detects it)

Recommended env vars:

- `CORS_ORIGIN=*`
- `YTMUSIC_GL=US`
- `YTMUSIC_HL=en`
- `STREAM_RESOLVER_ENABLED=true`
- `STREAM_PROXY_ENABLED=true`
- `YTDL_COOKIES_JSON=...` (secret)
- `YTMUSIC_COOKIES=...` (optional secret)

Important: Docker on Render solves bundling `yt-dlp`, but **does not guarantee playback**. YouTube may still return `403` for Render's datacenter IP. In practice, Render is great for metadata, while playback is often more reliable from a home/residential server.
