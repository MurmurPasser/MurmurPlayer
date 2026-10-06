import Foundation
import UIKit

/// Posiciones de reproducción para "Continuar viendo" y reanudar.
/// Solo publica cambios cuando se confirma una posición (cada ~10 s), no en cada fotograma,
/// para que la interfaz no se redibuje constantemente durante la reproducción.
final class PlaybackHistory: ObservableObject {
    static let shared = PlaybackHistory()

    @Published private(set) var entries: [String: HistoryEntry] = [:]
    private let storageKey = "mp.history.v1"
    private let maxEntries = 300
    /// Durante la reproducción se guarda en disco como mucho cada 60 s (en memoria, cada 10 s).
    private let persistInterval: TimeInterval = 60
    private var lastPersist = Date.distantPast

    private init() {
        load()
        // Si la app pasa a segundo plano o se cierra, no perder lo que quedó solo en memoria.
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.save()
        }
    }

    var recent: [HistoryEntry] {
        entries.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func entry(for key: String) -> HistoryEntry? {
        entries[key]
    }

    /// Posición para reanudar, o nil si no vale la pena (muy al inicio o ya terminado).
    func resumePosition(for key: String) -> Double? {
        guard let e = entries[key], !e.isFinished, e.position > 15 else { return nil }
        return e.position
    }

    /// `persist: false` actualiza la memoria y solo escribe en disco si pasó `persistInterval`.
    func record(key: String, title: String, source: PlaybackSource, position: Double, duration: Double,
                persist: Bool = true) {
        guard position.isFinite, duration.isFinite, duration > 0 else { return }
        var e = entries[key] ?? HistoryEntry(key: key, title: title, source: source, position: 0, duration: duration, updatedAt: Date())
        e.title = title
        e.source = source
        e.position = max(0, position)
        e.duration = duration
        e.updatedAt = Date()
        entries[key] = e
        trimIfNeeded()
        if persist || Date().timeIntervalSince(lastPersist) > persistInterval {
            save()
        }
    }

    /// Reemplaza el origen guardado (p. ej. un bookmark renovado) sin tocar el progreso.
    func updateSource(key: String, source: PlaybackSource) {
        guard var e = entries[key] else { return }
        e.source = source
        entries[key] = e
        save()
    }

    /// Al borrar un servidor, sus entradas ya no se pueden reproducir.
    func removeEntries(forServer serverID: UUID) {
        let before = entries.count
        entries = entries.filter { _, entry in
            if case let .smb(id, _, _) = entry.source { return id != serverID }
            return true
        }
        if entries.count != before { save() }
    }

    func markFinished(key: String) {
        guard var e = entries[key] else { return }
        e.position = e.duration
        e.updatedAt = Date()
        entries[key] = e
        save()
    }

    /// "Marcar como visto" desde el navegador, aunque nunca se haya reproducido.
    func markFinishedOrInsert(key: String, title: String, source: PlaybackSource) {
        if entries[key] != nil {
            markFinished(key: key)
        } else {
            entries[key] = HistoryEntry(key: key, title: title, source: source, position: 1, duration: 1, updatedAt: Date())
            save()
        }
    }

    func remove(key: String) {
        if let entry = entries[key] { forgetCredentials(of: entry) }
        entries[key] = nil
        save()
    }

    func clear() {
        entries.values.forEach(forgetCredentials)
        entries = [:]
        save()
    }

    private func forgetCredentials(of entry: HistoryEntry) {
        if case let .remote(url) = entry.source { RemoteCredentials.delete(for: url) }
    }

    private func trimIfNeeded() {
        guard entries.count > maxEntries else { return }
        let keep = Set(recent.prefix(maxEntries).map(\.key))
        entries.values.filter { !keep.contains($0.key) }.forEach(forgetCredentials)
        entries = entries.filter { keep.contains($0.key) }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: HistoryEntry].self, from: data)
        else { return }
        entries = decoded
        migrateRemotePasswords()
    }

    /// Versiones anteriores guardaban «Abrir URL» con la contraseña dentro.
    /// La pasa al llavero y vuelve a guardar el historial sin ella.
    private func migrateRemotePasswords() {
        var changed = false
        for (key, entry) in entries {
            guard case let .remote(string) = entry.source,
                  let url = URL(string: string), url.password != nil
            else { continue }
            let clean = RemoteCredentials.storeAndStrip(url).absoluteString
            entries[key] = nil
            entries[clean] = HistoryEntry(key: clean, title: entry.title, source: .remote(url: clean),
                                          position: entry.position, duration: entry.duration,
                                          updatedAt: entry.updatedAt)
            changed = true
        }
        if changed { save() }
    }

    private func save() {
        lastPersist = Date()
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
