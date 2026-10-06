import Foundation

/// Punto único para lanzar reproducciones desde cualquier pantalla.
final class PlaybackRouter: ObservableObject {
    static let shared = PlaybackRouter()

    @Published var current: PlayRequest?
    @Published var alertMessage: String?

    private init() {}

    func play(_ request: PlayRequest) {
        if current != nil {
            // Cerrar el reproductor actual antes de abrir otro
            current = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.current = request
            }
        } else {
            current = request
        }
    }

    // MARK: - Fuentes

    func playLocalFile(_ url: URL, needsSecurityScope: Bool) {
        let scoped = needsSecurityScope && url.startAccessingSecurityScopedResource()
        let source: PlaybackSource
        if let relative = LocalFiles.relativePath(of: url) {
            source = .documents(relativePath: relative)
        } else if let bookmark = try? url.bookmarkData() {
            source = .bookmark(data: bookmark, name: url.lastPathComponent)
        } else {
            source = .remote(url: url.absoluteString)
        }
        play(PlayRequest(url: url,
                         title: url.lastPathComponent,
                         historyKey: Self.historyKey(for: source, fallbackURL: url),
                         source: source,
                         securityScopedURL: scoped ? url : nil))
    }

    func playRemote(_ url: URL) {
        // El historial guarda la URL sin contraseña; la contraseña va al llavero.
        let source = PlaybackSource.remote(url: RemoteCredentials.storeAndStrip(url).absoluteString)
        play(PlayRequest(url: url,
                         title: url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent,
                         historyKey: Self.historyKey(for: source, fallbackURL: url),
                         source: source))
    }

    /// Archivos abiertos con "Abrir en…" desde Archivos u otras apps.
    func openExternal(_ url: URL) {
        if url.isFileURL {
            playLocalFile(url, needsSecurityScope: true)
        } else {
            playRemote(url)
        }
    }

    /// Reanuda desde "Continuar viendo".
    func resume(_ entry: HistoryEntry, fromStart: Bool = false) {
        switch entry.source {
        case let .smb(serverID, share, path):
            guard let server = ServerStore.shared.server(id: serverID) else {
                alertMessage = "El servidor de este video ya no está configurado."
                return
            }
            let password = ServerStore.shared.password(for: server)
            guard let url = server.playbackURL(share: share, path: path, password: password) else {
                alertMessage = "No se pudo construir la dirección del archivo."
                return
            }
            var request = PlayRequest(url: url, title: entry.title, historyKey: entry.key, source: entry.source)
            request.workgroup = server.domain
            request.forceStartAtZero = fromStart
            play(request)

        case let .documents(relativePath):
            let url = LocalFiles.documentsURL.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                alertMessage = "El archivo ya no existe en el iPad."
                return
            }
            var request = PlayRequest(url: url, title: entry.title, historyKey: entry.key, source: entry.source)
            request.forceStartAtZero = fromStart
            play(request)

        case let .bookmark(data, _):
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else {
                alertMessage = "No se pudo volver a abrir el archivo. Ábrelo de nuevo desde Archivos."
                return
            }
            let scoped = url.startAccessingSecurityScopedResource()
            var request = PlayRequest(url: url, title: entry.title, historyKey: entry.key, source: entry.source)
            request.securityScopedURL = scoped ? url : nil
            request.forceStartAtZero = fromStart
            play(request)

        case let .remote(string):
            guard let url = RemoteCredentials.restore(string) else { return }
            var request = PlayRequest(url: url, title: entry.title, historyKey: entry.key, source: entry.source)
            request.forceStartAtZero = fromStart
            play(request)
        }
    }

    static func historyKey(for source: PlaybackSource, fallbackURL: URL) -> String {
        switch source {
        case let .smb(serverID, share, path): return "smb://\(serverID.uuidString)/\(share)/\(path)"
        case let .documents(relativePath): return "docs://\(relativePath)"
        // Ruta completa, no solo el nombre: dos archivos homónimos en carpetas
        // distintas no deben compartir historial.
        case .bookmark: return "file://" + fallbackURL.standardizedFileURL.path
        case let .remote(url): return url
        }
    }
}

/// Contraseñas escritas a mano en «Abrir URL» (smb://usuario:clave@…):
/// se guardan en el llavero, nunca dentro del historial.
enum RemoteCredentials {
    private static func account(for url: String) -> String { "remote:" + url }

    /// La misma URL sin contraseña.
    static func strip(_ url: URL) -> URL {
        guard url.password != nil, var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        c.password = nil
        return c.url ?? url
    }

    /// Guarda la contraseña (si hay) en el llavero y devuelve la URL sin ella.
    static func storeAndStrip(_ url: URL) -> URL {
        let clean = strip(url)
        // URLComponents da la contraseña ya decodificada, igual que la espera restore().
        if let password = URLComponents(url: url, resolvingAgainstBaseURL: false)?.password, !password.isEmpty {
            Keychain.set(password, account: account(for: clean.absoluteString))
        }
        return clean
    }

    /// URL lista para reproducir: vuelve a poner la contraseña guardada.
    static func restore(_ string: String) -> URL? {
        guard let url = URL(string: string) else { return nil }
        guard url.password == nil, url.user != nil,
              let password = Keychain.get(account: account(for: string)),
              var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        c.password = password
        return c.url ?? url
    }

    static func delete(for string: String) {
        Keychain.delete(account: account(for: string))
    }
}

enum LocalFiles {
    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func relativePath(of url: URL) -> String? {
        let docs = documentsURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(docs + "/") else { return nil }
        return String(path.dropFirst(docs.count + 1))
    }

    static func listDocuments() -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: documentsURL,
                                             includingPropertiesForKeys: [.isRegularFileKey],
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator where MediaKind(fileName: url.lastPathComponent).isPlayable {
            result.append(url)
        }
        return result.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
