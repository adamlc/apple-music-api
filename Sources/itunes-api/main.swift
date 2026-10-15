import Foundation
import Hummingbird

let music = MusicScript()
let nowPlayingCache = NowPlayingCache(music: music)
let router = Router()
router.add(middleware: LogRequestsMiddleware(.info))

// MARK: - Helpers

func jsonResponse<T: Encodable>(_ value: T, status: HTTPResponse.Status = .ok) throws -> Response {
    let data = try JSONEncoder().encode(value)
    return Response(status: status, headers: [.contentType: "application/json"], body: .init(byteBuffer: .init(data: data)))
}

/// Form-encoded body fields (as sent by Home Assistant / curl -d), falling back to query parameters.
func formValues(_ request: Request) async throws -> [String: String] {
    var components = URLComponents()
    var buffer = try await request.body.collect(upTo: 1 << 16)
    components.query = buffer.readString(length: buffer.readableBytes)
    var values: [String: String] = [:]
    for item in components.queryItems ?? [] { values[item.name] = item.value ?? "" }
    for item in URLComponents(string: "?" + (request.uri.query ?? ""))?.queryItems ?? [] where values[item.name] == nil {
        values[item.name] = item.value ?? ""
    }
    return values
}

func parseBool(_ s: String?) -> Bool? {
    switch s?.lowercased() {
    case "true", "1", "yes", "on": return true
    case "false", "0", "no", "off": return false
    default: return nil
    }
}

/// Runs `body`, maps failures to HTTP errors.
func handle(_ body: () async throws -> Response) async -> Response {
    do {
        return try await body()
    } catch CommandError.badRequest(let message) {
        return Response(status: .badRequest, body: .init(byteBuffer: .init(string: message)))
    } catch {
        print("request failed: \(error)")
        return Response(status: .internalServerError)
    }
}

/// Runs a command, then responds with the fresh now-playing state (like the Node version).
/// `settle` gives Music a moment to finish changing track before we read its state back.
func command(settle: Duration = .zero, _ action: () async throws -> Void) async -> Response {
    await handle {
        try await action()
        if settle > .zero { try await Task.sleep(for: settle) }
        await nowPlayingCache.invalidate()
        return try jsonResponse(try await nowPlayingCache.get())
    }
}

// MARK: - Info

router.get("/_ping") { _, _ in "OK" }

router.get("/now_playing") { _, _ in
    await handle { try jsonResponse(try await nowPlayingCache.get()) }
}

router.get("/artwork") { _, _ in
    await handle {
        guard let art = try await music.artwork() else { return Response(status: .notFound) }
        return Response(status: .ok, headers: [.contentType: art.contentType], body: .init(byteBuffer: .init(data: art.data)))
    }
}

// MARK: - Player control

router.put("/play") { _, _ in await command(settle: .milliseconds(150)) { try await music.play() } }
router.put("/pause") { _, _ in await command(settle: .milliseconds(150)) { try await music.pause() } }
router.put("/playpause") { _, _ in await command(settle: .milliseconds(150)) { try await music.playPause() } }
router.put("/stop") { _, _ in await command(settle: .milliseconds(150)) { try await music.stop() } }
router.put("/previous") { _, _ in await command(settle: .milliseconds(250)) { try await music.previous() } }
router.put("/next") { _, _ in await command(settle: .milliseconds(250)) { try await music.next() } }

router.put("/volume") { request, _ in
    let form = try await formValues(request)
    return await command {
        guard let level = form["level"].flatMap({ Int($0) }) else {
            throw CommandError.badRequest("level is required")
        }
        try await music.setVolume(level)
    }
}

router.put("/mute") { request, _ in
    let form = try await formValues(request)
    return await command {
        guard let muted = parseBool(form["muted"]) else {
            throw CommandError.badRequest("muted must be true or false")
        }
        try await music.setMuted(muted)
    }
}

router.put("/shuffle") { request, _ in
    let form = try await formValues(request)
    return await command { try await music.setShuffle(form["mode"] ?? "songs") }
}

router.put("/repeat") { request, _ in
    let form = try await formValues(request)
    return await command(settle: .milliseconds(150)) { try await music.setRepeat(form["mode"] ?? "all") }
}

// MARK: - Playlists

router.get("/playlists") { _, _ in
    await handle { try jsonResponse(["playlists": try await music.playlists()]) }
}

router.put("/playlists/:id/play") { _, context in
    let id = context.parameters.get("id") ?? ""
    var found = true
    let response = await command(settle: .milliseconds(500)) { found = try await music.playPlaylist(id: id) }
    return found ? response : Response(status: .notFound)
}

// MARK: - AirPlay

router.get("/airplay_devices") { _, _ in
    await handle { try jsonResponse(["airplay_devices": try await music.airPlayDevices()]) }
}

router.get("/airplay_devices/:id") { _, context in
    await handle {
        guard let device = try await music.airPlayDevice(id: context.parameters.get("id") ?? "") else {
            return Response(status: .notFound)
        }
        return try jsonResponse(device)
    }
}

for (path, selected) in [("on", true), ("off", false)] {
    router.put("/airplay_devices/:id/\(path)") { _, context in
        await handle {
            guard let device = try await music.setAirPlayDevice(id: context.parameters.get("id") ?? "", selected: selected) else {
                return Response(status: .notFound)
            }
            return try jsonResponse(device)
        }
    }
}

router.put("/airplay_devices/:id/volume") { request, context in
    let form = try await formValues(request)
    return await handle {
        guard let level = form["level"].flatMap({ Int($0) }) else {
            throw CommandError.badRequest("level is required")
        }
        guard let device = try await music.setAirPlayDevice(id: context.parameters.get("id") ?? "", volume: level) else {
            return Response(status: .notFound)
        }
        return try jsonResponse(device)
    }
}

// MARK: - Server

let port = Int(ProcessInfo.processInfo.environment["PORT"] ?? "") ?? 10100
let app = Application(router: router, configuration: .init(address: .hostname("0.0.0.0", port: port)))
try await app.runService()
