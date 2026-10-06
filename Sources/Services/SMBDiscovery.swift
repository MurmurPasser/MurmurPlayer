import Foundation

/// Busca NAS/PCs que anuncian SMB por Bonjour (_smb._tcp) y resuelve su IP.
final class SMBDiscovery: NSObject, ObservableObject {
    struct Found: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let host: String
    }

    @Published private(set) var found: [Found] = []
    @Published private(set) var isSearching = false

    private var browser: NetServiceBrowser?
    private var resolving: [NetService] = []

    func start() {
        stop()
        found = []
        let browser = NetServiceBrowser()
        browser.delegate = self
        self.browser = browser
        isSearching = true
        browser.searchForServices(ofType: "_smb._tcp.", inDomain: "local.")
    }

    func stop() {
        browser?.stop()
        browser = nil
        resolving.forEach { $0.stop() }
        resolving.removeAll()
        isSearching = false
    }

    deinit {
        browser?.stop()
    }

    /// Extrae la primera IPv4 de las direcciones resueltas (más fiable que el nombre .local).
    private static func ipv4(from addresses: [Data]?) -> String? {
        guard let addresses else { return nil }
        for data in addresses where data.count >= MemoryLayout<sockaddr_in>.size {
            var sin = sockaddr_in()
            withUnsafeMutableBytes(of: &sin) { buffer in
                buffer.copyBytes(from: data.prefix(MemoryLayout<sockaddr_in>.size))
            }
            guard sin.sin_family == sa_family_t(AF_INET) else { continue }
            var address = sin.sin_addr
            var chars = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            if inet_ntop(AF_INET, &address, &chars, socklen_t(INET_ADDRSTRLEN)) != nil {
                return String(cString: chars)
            }
        }
        return nil
    }
}

extension SMBDiscovery: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(_: NetServiceBrowser, didFind service: NetService, moreComing _: Bool) {
        service.delegate = self
        resolving.append(service)
        service.resolve(withTimeout: 6)
    }

    func netServiceBrowser(_: NetServiceBrowser, didRemove service: NetService, moreComing _: Bool) {
        found.removeAll { $0.name == service.name }
    }

    func netServiceBrowserDidStopSearch(_: NetServiceBrowser) {
        isSearching = false
    }

    func netServiceBrowser(_: NetServiceBrowser, didNotSearch _: [String: NSNumber]) {
        isSearching = false
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let host: String
        if let ip = Self.ipv4(from: sender.addresses) {
            host = ip
        } else if let name = sender.hostName {
            host = name.hasSuffix(".") ? String(name.dropLast()) : name
        } else {
            return
        }
        let item = Found(name: sender.name, host: host)
        if !found.contains(where: { $0.name == item.name }) {
            found.append(item)
            found.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        sender.stop()
        resolving.removeAll { $0 === sender }
    }

    func netService(_ sender: NetService, didNotResolve _: [String: NSNumber]) {
        resolving.removeAll { $0 === sender }
    }
}
