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
