# IOS_APP

Native iOS client prototype (`SwiftUI + AVPlayer`) wired to the deployed backend:

- Server URL: `https://music-brre.onrender.com`
- Search songs (`/api/search?type=songs`)
- Resolve playback (`/api/playback/:videoId/resolve`)
- Native playback engine (`AVPlayer`)
- Background audio mode + lock screen remote controls hooks

## Generate Project

```bash
cd IOS_APP
xcodegen generate
open MusicIOS.xcodeproj
```

## Run

1. Select an iPhone simulator or device in Xcode
2. Build & Run
3. Open `Search`
4. Search for a song and tap it to play

## Notes

- The app currently prefers `proxyUrl` if present, otherwise uses `directUrl`.
- Your backend currently returns `proxyUrl: null` (`STREAM_PROXY_ENABLED=false`), so playback uses direct stream URLs.
- If playback fails on a real iPhone due to IP-bound URLs, enable proxy playback on the server and redeploy.
