import SwiftUI

enum SidebarItem: Hashable {
    case recents, local, openURL, settings
    case server(UUID)
}

struct RootView: View {
    @EnvironmentObject private var servers: ServerStore
    @EnvironmentObject private var router: PlaybackRouter

    @State private var selection: SidebarItem? = .recents
    @State private var editingServer: SMBServer?
    @State private var showingNewServer = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Biblioteca") {
                    Label("Continuar viendo", systemImage: "clock.arrow.circlepath")
                        .tag(SidebarItem.recents)
                    Label("En este iPad", systemImage: "ipad.landscape")
                        .tag(SidebarItem.local)
                    Label("Abrir URL", systemImage: "link")
                        .tag(SidebarItem.openURL)
                }

                Section("Servidores") {
                    ForEach(servers.servers) { server in
                        Label(server.name, systemImage: "server.rack")
                            .tag(SidebarItem.server(server.id))
                            .contextMenu {
                                Button {
                                    editingServer = server
                                } label: {
                                    Label("Editar", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    if selection == .server(server.id) { selection = .recents }
                                    servers.delete(server)
                                } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            }
                    }
                    Button {
                        showingNewServer = true
                    } label: {
                        Label("Añadir servidor", systemImage: "plus.circle")
                    }
                }

                Section {
                    Label("Ajustes", systemImage: "gearshape")
                        .tag(SidebarItem.settings)
                }
            }
            .navigationTitle("Murmur Player")
        } detail: {
            NavigationStack {
                detail
            }
            .id(selection)
        }
        .sheet(isPresented: $showingNewServer) {
            ServerEditView(server: nil) { saved in
                selection = .server(saved.id)
            }
        }
        .sheet(item: $editingServer) { server in
            ServerEditView(server: server) { _ in }
        }
        .fullScreenCover(item: $router.current) { request in
            PlayerScreen(request: request)
        }
        .alert("Murmur Player", isPresented: Binding(
            get: { router.alertMessage != nil },
            set: { if !$0 { router.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(router.alertMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .recents, .none:
            RecentsView()
        case .local:
            LocalLibraryView()
        case .openURL:
            OpenURLView()
        case .settings:
            SettingsView()
        case let .server(id):
            if let server = servers.server(id: id) {
                ServerBrowserView(server: server) {
                    editingServer = server
                }
                .id(server) // si se edita el servidor, se reconecta
            } else {
                MessageStateView(symbol: "server.rack", title: "Servidor no encontrado", message: nil)
            }
        }
    }
}

/// Estado vacío / error reutilizable (ContentUnavailableView solo existe desde iOS 17).
struct MessageStateView: View {
    let symbol: String
    let title: String
    let message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Barra fina de progreso para "visto hasta aquí".
struct WatchProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule().fill(Color.accentColor)
                    .frame(width: max(3, proxy.size.width * progress))
            }
        }
        .frame(height: 3)
    }
}
