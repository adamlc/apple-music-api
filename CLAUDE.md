# apple-music-api

Swift menu bar app that serves an HTTP API for the macOS Music app. It's a drop-in replacement for
[maddox/itunes-api](https://github.com/maddox/itunes-api) (Node) for Home Assistant's legacy
[iTunes integration](https://www.home-assistant.io/integrations/itunes/), so the JSON shapes and
endpoints must stay compatible with what that integration sends and reads.

The maintainer is newer to Swift, so keep code simple and explain Swift-specific choices.

## Commands

    swift test              # unit tests; they never talk to Music
    script/bundle           # build/Apple Music API.app (signed ad hoc)
    script/install          # bundle, copy to ~/Applications, quit the running copy, start the new one

The port is set from the menu bar (saved in user defaults, default 8181); there is no env var or flag.
To test a build without disturbing the installed app, quit the installed one from its menu bar item,
run `open "build/Apple Music API.app"`, and run `script/install` afterwards to put the installed copy
back. Testing against a real Music changes what's playing, AirPlay selection and volume, so put
things back (volume, shuffle, repeat, AirPlay devices) afterwards.

## Things that are easy to get wrong

**Apple Events**
- `NSAppleScript` must run on the main thread. On a background queue it hangs forever waiting for
  Music's reply. `MusicScript` runs everything on `DispatchQueue.main`.
- Never ask for `properties of current track`: it includes lyrics and takes ~2.8s. Fetch only the
  fields needed, in one script per request.
- Bulk fetches (`{id, name} of every playlist`) are far faster than looping. AirPlay devices need a
  loop, because enum properties like `kind` can't be bulk-fetched as text.
- Music's `mute` can't be set to `true` on current macOS (error 9038, from Music itself). `setMuted`
  falls back to emulating mute by setting volume to 0 and restoring it on unmute.
- Music reorders `AirPlay devices` when one is selected, so after a change look the device up by id
  again. Index-based lookup returns the wrong device.
- Music applies some changes a moment late (track changes, repeat, stop), so commands `settle` for
  150-500ms before reading state back.
- Any `tell application "Music"` launches Music. Polling must not reopen a Music the user quit, so
  `run()` throws `MusicNotRunning` unless the caller passes `launchIfNeeded`. Only `play`,
  `playpause` and playlist play do, via `ensureRunning()`, which waits ~3s for startup (commands sent
  while Music is still launching get dropped or overridden). `/now_playing` reports `stopped` when
  Music isn't running; other endpoints return 503.

**Home Assistant compatibility**
- `/now_playing` `shuffle` must be the mode string (`"songs"`) or `false`, never `true`. HA only
  treats it as on when it equals `"songs"`.
- HA's client sends `PUT` fields as a form-encoded *body*, not query params. Both are accepted.
- HA matches `play_media` playlists by id or name from `GET /playlists`. Ids are slugs of the name;
  duplicates keep the plain slug for the first and get a persistent-id suffix after that.
- HA requests `/artwork?id=...`; the query is ignored.
- Streamed Apple Music catalog tracks (AppleScript class `URL track`) report zero artworks, so
  `/artwork` falls back to Apple's iTunes Search API (`ArtworkSearch`), matching on artist, title and
  preferably album, and caches by persistent id. Library tracks use the embedded artwork.

**macOS permissions and signing**
- The "control Music" permission is tied to the responsible process. Launch the app with `open` (or
  as a login item), never by running the binary from a terminal, or the permission is attributed to
  the terminal.
- The hardened runtime needs `com.apple.security.automation.apple-events`
  (`Resources/apple-music-api.entitlements`), or the app can't control Music.
- Signing is ad hoc (no Developer ID). Rebuilds change the signature, so macOS may ask for
  permission again. Set `SIGN_IDENTITY` to a stable certificate to avoid that.
- Bundle id is `uk.co.adamlc.apple-music-api`. Reset permission with
  `tccutil reset AppleEvents uk.co.adamlc.apple-music-api`.
- Start at Login uses `SMAppService.mainApp`, so it points at wherever the app is running from.
  Enable it from the copy in `~/Applications`, not `build/`.

**Icons**
- The app icon and menu bar glyph are drawn in code (`IconArtwork.swift`). `script/bundle` runs the
  binary with `--render-icons <dir>` and `iconutil` to make the `.icns`. To look at the icon, run
  that command and open `AppIcon-1024.png`. Overlapping subpaths in one `NSBezierPath` cancel out
  where winding differs, so the note is drawn as separate shapes inside one transparency layer.

## Repo

- Repo: github.com/adamlc/apple-music-api.
- The old Node app and an abandoned Go rewrite live separately in `~/Sites/itunes-api`; they are not
  part of this repo.
- Not done: Developer ID signing and notarization (needed to distribute to others), and a Home
  Assistant playlist picker (HA's iTunes integration has no browse-media support, so it would need
  scripts, an `input_select`, or a custom integration).
