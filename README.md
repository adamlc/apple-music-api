# itunes-api (Swift)

A small macOS HTTP server for querying and controlling the Music app, written in Swift.
It is a rewrite of [maddox/itunes-api](https://github.com/maddox/itunes-api) (Node), intended for
use with the Home Assistant [iTunes integration](https://www.home-assistant.io/integrations/itunes/).

It talks to Music in-process via AppleScript (`NSAppleScript`) and serves JSON with
[Hummingbird](https://github.com/hummingbird-project/hummingbird).

## Status

Prototype. Implemented:

- `GET /_ping`
- `GET /now_playing`

Still to port from the Node version: play/pause/playpause/stop/next/previous, volume, mute,
shuffle, repeat, playlists, AirPlay devices and artwork.

## Running

Requires macOS 14+ and Xcode (for the Swift toolchain).

    swift build -c release
    PORT=10100 .build/release/itunes-api

`PORT` defaults to `10100`.

macOS will ask for permission to control Music. When launched from a terminal, that permission is
attributed to the terminal app, not this binary. Bundling it as a signed `.app` is planned so it gets
its own permission prompt.

## Notes

- AppleScript must run on the main thread. Running it on a background queue hangs while waiting for
  Music's reply.
- Fetching `properties of current track` takes ~2.8s because it includes lyrics and dates. Ask only for
  the fields you need; `/now_playing` does this in a single script and takes ~0.14s.

## Licence

MIT, see [LICENSE](LICENSE).
