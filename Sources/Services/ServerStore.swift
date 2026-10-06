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

    static func set(_ value: String, account: String) {
        let query = baseQuery(account)
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
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

    static func delete(account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}

final class ServerStore: ObservableObject {
    static let shared = ServerStore()

    @Published private(set) var servers: [SMBServer] = []
    private let storageKey = "mp.servers.v1"

    private init() {
        load()
    }

    func server(id: UUID) -> SMBServer? {
        servers.first { $0.id == id }
    }

    func password(for server: SMBServer) -> String {
        Keychain.get(account: server.id.uuidString) ?? ""
    }

    /// `password == nil` deja la contraseña guardada tal como estaba.
    func upsert(_ server: SMBServer, password: String?) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        if let password {
            Keychain.set(password, account: server.id.uuidString)
        }
        save()
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
