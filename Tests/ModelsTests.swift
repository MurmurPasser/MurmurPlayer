@testable import MurmurPlayer
import XCTest

final class CleanHostTests: XCTestCase {
    private func clean(_ host: String) -> String {
        SMBServer(name: "", host: host, port: nil, username: "", domain: "", defaultShare: "").cleanHost
    }

    func testPlainHost() {
        XCTAssertEqual(clean("192.168.1.5"), "192.168.1.5")
        XCTAssertEqual(clean("  nas.local \n"), "nas.local")
    }

    func testStripsSchemeUserPathAndPort() {
        XCTAssertEqual(clean("smb://usuario@nas/Videos"), "nas")
        XCTAssertEqual(clean("192.168.1.5/Videos"), "192.168.1.5")
        XCTAssertEqual(clean("usuario@nas"), "nas")
        XCTAssertEqual(clean("nas:445"), "nas")
        XCTAssertEqual(clean("\\\\nas\\Videos"), "nas")
        XCTAssertEqual(clean("SMB://nas/"), "nas")
    }

    func testLeavesIPv6Alone() {
        XCTAssertEqual(clean("fe80::1"), "fe80::1")
    }
}

final class PlaybackURLTests: XCTestCase {
    func testIncludesCredentialsShareAndPath() throws {
        let server = SMBServer(name: "NAS", host: "nas", port: nil, username: "ana", domain: "", defaultShare: "")
        let url = try XCTUnwrap(server.playbackURL(share: "video", path: "Pelis/Dune 2.mkv", password: "p@ss:1"))
        XCTAssertEqual(url.scheme, "smb")
        XCTAssertEqual(url.host, "nas")
        XCTAssertEqual(url.user, "ana")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.password, "p@ss:1")
        XCTAssertEqual(url.path, "/video/Pelis/Dune 2.mkv")
    }

    func testCustomPortAndGuest() throws {
        let server = SMBServer(name: "NAS", host: "nas", port: 4455, username: "", domain: "", defaultShare: "")
        let url = try XCTUnwrap(server.playbackURL(share: "video", path: "", password: "ignorada"))
        XCTAssertEqual(url.port, 4455)
        XCTAssertNil(url.user)
        XCTAssertNil(url.password)
        XCTAssertEqual(url.path, "/video")
    }
}

final class HistoryEntryTests: XCTestCase {
    private func entry(position: Double, duration: Double) -> HistoryEntry {
        HistoryEntry(key: "k", title: "t", source: .remote(url: "https://x/y.mp4"),
                     position: position, duration: duration, updatedAt: Date())
    }

    func testShortClipIsNotFinishedAtStart() {
        XCTAssertFalse(entry(position: 0, duration: 40).isFinished)
        XCTAssertFalse(entry(position: 20, duration: 40).isFinished)
        XCTAssertTrue(entry(position: 39, duration: 40).isFinished)
    }

    func testLongVideoFinishesInCredits() {
        XCTAssertFalse(entry(position: 3000, duration: 3600).isFinished)
        XCTAssertTrue(entry(position: 3560, duration: 3600).isFinished)
    }

    func testZeroDurationIsNeverFinished() {
        XCTAssertFalse(entry(position: 0, duration: 0).isFinished)
    }

    func testProgressIsClamped() {
        XCTAssertEqual(entry(position: 50, duration: 100).progress, 0.5)
        XCTAssertEqual(entry(position: 150, duration: 100).progress, 1)
        XCTAssertEqual(entry(position: 10, duration: 0).progress, 0)
    }
}

final class HistoryKeyTests: XCTestCase {
    func testBookmarkKeyUsesFullPath() {
        let a = URL(fileURLWithPath: "/Temporada 1/E01.mkv")
        let b = URL(fileURLWithPath: "/Temporada 2/E01.mkv")
        let keyA = PlaybackRouter.historyKey(for: .bookmark(data: Data(), name: "E01.mkv"), fallbackURL: a)
        let keyB = PlaybackRouter.historyKey(for: .bookmark(data: Data(), name: "E01.mkv"), fallbackURL: b)
        XCTAssertNotEqual(keyA, keyB)
    }

    func testSMBKey() {
        let id = UUID()
        let key = PlaybackRouter.historyKey(for: .smb(serverID: id, share: "video", path: "a/b.mkv"),
                                            fallbackURL: URL(fileURLWithPath: "/"))
        XCTAssertEqual(key, "smb://\(id.uuidString)/video/a/b.mkv")
    }
}

final class RemoteCredentialsTests: XCTestCase {
    func testStripRemovesOnlyPassword() throws {
        let url = try XCTUnwrap(URL(string: "smb://ana:secreta@nas/video/peli.mkv"))
        let clean = RemoteCredentials.strip(url)
        XCTAssertEqual(clean.absoluteString, "smb://ana@nas/video/peli.mkv")
        XCTAssertFalse(clean.absoluteString.contains("secreta"))
    }

    func testStripLeavesURLWithoutPasswordUntouched() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/video.m3u8"))
        XCTAssertEqual(RemoteCredentials.strip(url), url)
    }
}

final class MediaKindTests: XCTestCase {
    func testClassifiesByExtension() {
        XCTAssertEqual(MediaKind(fileName: "Peli.MKV"), .video)
        XCTAssertEqual(MediaKind(fileName: "tema.flac"), .audio)
        XCTAssertEqual(MediaKind(fileName: "Peli.es.srt"), .subtitle)
        XCTAssertEqual(MediaKind(fileName: "notas.txt"), .other)
        XCTAssertTrue(MediaKind(fileName: "a.mp4").isPlayable)
        XCTAssertFalse(MediaKind(fileName: "a.srt").isPlayable)
    }
}

final class FormattersTests: XCTestCase {
    func testTime() {
        XCTAssertEqual(Formatters.time(0), "0:00")
        XCTAssertEqual(Formatters.time(65), "1:05")
        XCTAssertEqual(Formatters.time(3725), "1:02:05")
        XCTAssertEqual(Formatters.time(.nan), "--:--")
        XCTAssertEqual(Formatters.time(-1), "--:--")
    }
}
