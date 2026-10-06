import Foundation
import Security

/// Contraseñas en el llavero del sistema (nunca en UserDefaults).
enum Keychain {
    private static let service = "com.murmur.player.smb"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Devuelve false si el llavero rechazó la contraseña.
    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        let query = baseQuery(account)
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return true }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        // ThisDeviceOnly: la contraseña no viaja en copias de seguridad ni a otro dispositivo.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func get(account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Las versiones anteriores guardaban con `AfterFirstUnlock` (entra en copias de seguridad).
    /// Pasa todas las contraseñas de la app a `ThisDeviceOnly`; se ejecuta una sola vez.
    static func migrateToThisDeviceOnly() {
        let flag = "mp.keychain.thisDeviceOnly"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            UserDefaults.standard.set(true, forKey: flag)
        }
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}

final class ServerStore: ObservableObject {
    static let shared = ServerStore()

    @Published private(set) var servers: [SMBServer] = []
    private let storageKey = "mp.servers.v1"

    private init() {
        Keychain.migrateToThisDeviceOnly()
        load()
    }

    func server(id: UUID) -> SMBServer? {
        servers.first { $0.id == id }
    }

    func password(for server: SMBServer) -> String {
        Keychain.get(account: server.id.uuidString) ?? ""
    }

    /// `password == nil` deja la contraseña guardada tal como estaba.
    /// Devuelve false si el servidor se guardó pero la contraseña no.
    @discardableResult
    func upsert(_ server: SMBServer, password: String?) -> Bool {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        var passwordSaved = true
        if let password {
            passwordSaved = Keychain.set(password, account: server.id.uuidString)
        }
        save()
        return passwordSaved
    }

    func delete(_ server: SMBServer) {
        Keychain.delete(account: server.id.uuidString)
        PlaybackHistory.shared.removeEntries(forServer: server.id)
        servers.removeAll { $0.id == server.id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SMBServer].self, from: data)
        else { return }
        servers = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
