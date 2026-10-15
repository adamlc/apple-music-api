import Foundation
import Hummingbird

let music = MusicScript()
let router = Router()

router.get("/_ping") { _, _ in "OK" }

router.get("/now_playing") { _, _ -> Response in
    do {
        let np = try await music.nowPlaying()
        let data = try JSONEncoder().encode(np)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: .init(data: data)))
    } catch {
        print("now_playing failed: \(error)")
        return Response(status: .internalServerError)
    }
}

let port = Int(ProcessInfo.processInfo.environment["PORT"] ?? "") ?? 10100
let app = Application(router: router, configuration: .init(address: .hostname("0.0.0.0", port: port)))
try await app.runService()
