import Foundation

// MARK: - Servidor SMB

struct SMBServer: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var host: String
    /// nil = puerto estándar 445
    var port: Int?
    var username: String
    /// Dominio o grupo de trabajo (opcional, casi siempre vacío en un NAS doméstico)
    var domain: String
    /// Si se define, el navegador abre directamente este recurso compartido
    var defaultShare: String

    /// Solo el nombre o la IP, aunque el usuario escriba "smb://usuario@nas/Videos",
    /// `\\nas\Videos` o "nas:445".
    var cleanHost: String {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        if let scheme = h.range(of: "://") { h = String(h[scheme.upperBound...]) }
        h = h.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let slash = h.firstIndex(of: "/") { h = String(h[..<slash]) }
        if let at = h.lastIndex(of: "@") { h = String(h[h.index(after: at)...]) }
        // "nas:445" → "nas" (el puerto va en su propio campo). No toca IPv6.
        if h.filter({ $0 == ":" }).count == 1, let colon = h.firstIndex(of: ":") {
            h = String(h[..<colon])
        }
        return h
    }

    /// URL base para AMSMB2 (sin credenciales).
    var managerURL: URL? {
        var c = URLComponents()
        c.scheme = "smb"
        c.host = cleanHost
        if let port, port != 445 { c.port = port }
        return c.url
    }

    /// URL completa que entiende FFmpeg (libsmbclient): smb://user:pass@host/share/ruta
    func playbackURL(share: String, path: String, password: String) -> URL? {
        var c = URLComponents()
        c.scheme = "smb"
        c.host = cleanHost
        if let port, port != 445 { c.port = port }
        let user = username.trimmingCharacters(in: .whitespaces)
        if !user.isEmpty {
            c.user = user
            if !password.isEmpty { c.password = password }
        }
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        c.path = "/" + share + (trimmed.isEmpty ? "" : "/" + trimmed)
        return c.url
    }
}

// MARK: - Origen de una reproducción (para reanudar desde "Continuar viendo")

enum PlaybackSource: Codable, Hashable {
    case smb(serverID: UUID, share: String, path: String)
    case documents(relativePath: String)
    case bookmark(data: Data, name: String)
    case remote(url: String)
}

// MARK: - Petición de reproducción

struct PlayRequest: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let historyKey: String
    let source: PlaybackSource
    var subtitleFiles: [URL] = []
    var workgroup: String = ""
    var forceStartAtZero = false
    /// URL con acceso "security-scoped" abierto (archivos elegidos desde la app Archivos)
    var securityScopedURL: URL?
}

// MARK: - Historial / reanudar

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id: String { key }
    let key: String
    var title: String
    var source: PlaybackSource
    var position: Double
    var duration: Double
    var updatedAt: Date

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }

    var isFinished: Bool {
        guard duration > 0 else { return false }
        if position >= duration * 0.95 { return true }
        // Los últimos 45 s (créditos) solo cuentan en videos largos; en clips
        // cortos marcarían como visto algo apenas empezado.
        return duration >= 600 && duration - position < 45
    }
}

// MARK: - Tipos de archivo

enum MediaKind {
    case video, audio, subtitle, other

    static let videoExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "mov", "avi", "wmv", "flv", "webm", "ts", "m2ts", "mts",
        "mpg", "mpeg", "vob", "3gp", "ogv", "rmvb", "rm", "divx", "f4v", "hevc", "264", "265",
    ]
    static let audioExtensions: Set<String> = [
        "mp3", "flac", "aac", "m4a", "wav", "ogg", "opus", "alac", "ape", "wma", "aiff", "aif", "dsf", "dff",
    ]
    /// Solo subtítulos de texto (los de imagen como PGS van embebidos en el contenedor).
    static let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "vtt"]

    init(fileName: String) {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if Self.videoExtensions.contains(ext) {
            self = .video
        } else if Self.audioExtensions.contains(ext) {
            self = .audio
        } else if Self.subtitleExtensions.contains(ext) {
            self = .subtitle
        } else {
            self = .other
        }
    }

    var isPlayable: Bool { self == .video || self == .audio }

    var symbol: String {
        switch self {
        case .video: return "film"
        case .audio: return "music.note"
        case .subtitle: return "captions.bubble"
        case .other: return "doc"
        }
    }
}

// MARK: - Formato

enum Formatters {
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static let relativeDate: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
