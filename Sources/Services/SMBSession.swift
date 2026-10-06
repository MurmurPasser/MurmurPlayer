import AMSMB2
import Foundation

struct SMBEntry: Identifiable, Hashable {
    var id: String { path }
    let name: String
    /// Ruta relativa al recurso compartido, sin "/" inicial. Ej: "Peliculas/Dune.mkv"
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date?

    var kind: MediaKind { isDirectory ? .other : MediaKind(fileName: name) }
}

enum SMBError: LocalizedError {
    case invalidHost

    var errorDescription: String? {
        switch self {
        case .invalidHost: return "La dirección del servidor no es válida."
        }
    }

    /// Traduce los errores POSIX de libsmb2 a mensajes útiles.
    static func friendly(_ error: Error) -> String {
        if let posix = error as? POSIXError {
            switch posix.code {
            case .EACCES, .EPERM, .EAUTH:
                return "Acceso denegado. Revisa el usuario y la contraseña."
            case .ECONNREFUSED, .ETIMEDOUT, .EHOSTUNREACH, .ENETUNREACH, .EHOSTDOWN, .ECONNRESET:
                return "No se pudo conectar al servidor. Verifica la IP, que el dispositivo esté en la misma red y que Murmur Player tenga permiso de Red local (Ajustes › Privacidad y seguridad › Red local)."
            case .ENOENT:
                return "La carpeta o el recurso compartido no existe."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

/// Una conexión a un servidor. SMB2Manager es thread-safe; el lock solo protege el share activo.
final class SMBSession: @unchecked Sendable {
    let server: SMBServer
    private let manager: SMB2Manager
    private var connectedShare: String?
    private let lock = NSLock()

    init(server: SMBServer, password: String) throws {
        guard let url = server.managerURL else { throw SMBError.invalidHost }
        let user = server.username.trimmingCharacters(in: .whitespaces)
        let credential = URLCredential(user: user.isEmpty ? "guest" : user,
                                       password: password,
                                       persistence: .forSession)
        guard let manager = SMB2Manager(url: url, domain: server.domain, credential: credential) else {
            throw SMBError.invalidHost
        }
        self.server = server
        self.manager = manager
    }

    deinit {
        let manager = self.manager
        Task { try? await manager.disconnectShare() }
    }

    func listShares() async throws -> [String] {
        let shares = try await manager.listShares()
        return shares.map { $0.name }
            .filter { !$0.hasSuffix("$") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var currentShare: String? {
        lock.lock(); defer { lock.unlock() }
        return connectedShare
    }

    private func setCurrentShare(_ share: String?) {
        lock.lock(); connectedShare = share; lock.unlock()
    }

    private func ensureConnected(to share: String) async throws {
        if currentShare == share { return }
        if currentShare != nil {
            try? await manager.disconnectShare()
            setCurrentShare(nil)
        }
        try await manager.connectShare(name: share)
        setCurrentShare(share)
    }

    func contents(share: String, path: String) async throws -> [SMBEntry] {
        try await ensureConnected(to: share)
        let raw = try await manager.contentsOfDirectory(atPath: "/" + path)
        return raw.compactMap { item -> SMBEntry? in
            guard let name = item[.nameKey] as? String else { return nil }
            // Ocultos, papelera y miniaturas de Synology/QNAP
            if name.hasPrefix(".") || name.hasPrefix("@") || name.hasPrefix("#") || name.hasPrefix("$") {
                return nil
            }
            let isDirectory = (item[.isDirectoryKey] as? NSNumber)?.boolValue ?? false
            let size = (item[.fileSizeKey] as? NSNumber)?.int64Value ?? 0
            let modified = item[.contentModificationDateKey] as? Date
            let childPath = path.isEmpty ? name : path + "/" + name
            return SMBEntry(name: name, path: childPath, isDirectory: isDirectory, size: size, modified: modified)
        }
    }

    func download(share: String, path: String, to localURL: URL) async throws {
        try await ensureConnected(to: share)
        try await manager.downloadItem(atPath: "/" + path, to: localURL, progress: nil)
    }
}

/// Descarga los subtítulos de texto que acompañan a un video en la misma carpeta
/// (Pelicula.srt, Pelicula.es.srt, Pelicula.forced.ass…). FFmpeg ya lee los embebidos.
enum SubtitleFetcher {
    static func siblings(for video: SMBEntry, in entries: [SMBEntry], session: SMBSession, share: String) async -> [URL] {
        let base = (video.name as NSString).deletingPathExtension.lowercased()
        let candidates = entries.filter {
            !$0.isDirectory && $0.kind == .subtitle && $0.size < 10_000_000
                && ($0.name as NSString).deletingPathExtension.lowercased().hasPrefix(base)
        }.prefix(8)
        guard !candidates.isEmpty else { return [] }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("subs", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var result: [URL] = []
        for candidate in candidates {
            let destination = dir.appendingPathComponent(candidate.name)
            do {
                try await session.download(share: share, path: candidate.path, to: destination)
                result.append(destination)
            } catch {
                continue
            }
        }
        return result
    }
}
