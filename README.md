# itunes-api (Swift)

A small macOS HTTP server for querying and controlling the Music app, written in Swift.
It is a rewrite of [maddox/itunes-api](https://github.com/maddox/itunes-api) (Node), intended for
use with the Home Assistant [iTunes integration](https://www.home-assistant.io/integrations/itunes/).

It talks to Music in-process via AppleScript (`NSAppleScript`) and serves JSON with
[Hummingbird](https://github.com/hummingbird-project/hummingbird).

## API

Matches the Node version. `PUT` endpoints that change playback return the same JSON as `/now_playing`.
Form fields can be sent as `application/x-www-form-urlencoded` bodies or query parameters.

    GET /_ping
    GET /now_playing                 (cached for 1s; cleared by any command)
    GET /artwork                     (image bytes, 404 if none)
    PUT /play | /pause | /playpause | /stop | /previous | /next
    PUT /volume          level=0-100
    PUT /mute            muted=true|false
    PUT /shuffle         mode=songs|albums|groupings|off
    PUT /repeat          mode=all|one|off
    GET /playlists
    PUT /playlists/:id/play
    GET /airplay_devices
    GET /airplay_devices/:id
    PUT /airplay_devices/:id/on | /off
    PUT /airplay_devices/:id/volume    level=0-100

Differences from the Node version: unknown playlists or AirPlay devices return 404 (Node returned an
empty object for AirPlay), invalid parameters return 400, and playlist `loved` uses the playlist's
`favorited` flag.

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
