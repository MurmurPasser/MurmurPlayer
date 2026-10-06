import UIKit
import SwiftUI

enum BrowserSort: String, CaseIterable, Identifiable {
    case name, newest, largest
    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Nombre"
        case .newest: return "Más recientes"
        case .largest: return "Más grandes"
        }
    }
}

struct ServerBrowserView: View {
    let server: SMBServer
    let onEdit: () -> Void

    @State private var session: SMBSession?
    @State private var shares: [String] = []
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        Group {
            if loading {
                ProgressView("Conectando a \(server.cleanHost)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText {
                MessageStateView(symbol: "wifi.exclamationmark",
                                 title: "Sin conexión",
                                 message: errorText,
                                 actionTitle: "Reintentar") {
                    Task { await connect() }
                }
            } else if let session {
                if !server.defaultShare.isEmpty {
                    FolderView(session: session, share: server.defaultShare, path: "")
                } else {
                    sharesList(session)
                }
            }
        }
        .navigationTitle(server.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Editar servidor")
            }
        }
        .task {
            if session == nil { await connect() }
        }
    }

    private func sharesList(_ session: SMBSession) -> some View {
        List {
            if shares.isEmpty {
                Text("El servidor no mostró recursos compartidos. Indica uno en «Carpeta inicial» al editar el servidor.")
                    .foregroundStyle(.secondary)
            }
            ForEach(shares, id: \.self) { share in
                NavigationLink {
                    FolderView(session: session, share: share, path: "")
                } label: {
                    Label(share, systemImage: "externaldrive.fill")
                }
            }
        }
        .refreshable { await connect() }
    }

    private func connect() async {
        loading = session == nil
        errorText = nil
        do {
            let newSession = try SMBSession(server: server, password: ServerStore.shared.password(for: server))
            if server.defaultShare.isEmpty {
                shares = try await newSession.listShares()
            }
            session = newSession
        } catch {
            errorText = SMBError.friendly(error)
        }
        loading = false
    }
}

struct FolderView: View {
    let session: SMBSession
    let share: String
    let path: String

    @EnvironmentObject private var history: PlaybackHistory
    @AppStorage(PlayerSettings.Keys.showAllFiles) private var showAllFiles = false
    @AppStorage(PlayerSettings.Keys.browserSort) private var sortRaw = BrowserSort.name.rawValue

    @State private var entries: [SMBEntry] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var query = ""
    @State private var preparingID: String?

    private var title: String {
        path.isEmpty ? share : (path as NSString).lastPathComponent
    }

    private var sort: BrowserSort {
        BrowserSort(rawValue: sortRaw) ?? .name
    }

    private var visibleEntries: [SMBEntry] {
        var items = entries.filter { $0.isDirectory || showAllFiles || $0.kind.isPlayable }
        if !query.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        let folders = items.filter(\.isDirectory)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let files = items.filter { !$0.isDirectory }.sorted { a, b in
            switch sort {
            case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .newest: return (a.modified ?? .distantPast) > (b.modified ?? .distantPast)
            case .largest: return a.size > b.size
            }
        }
        return folders + files
    }

    var body: some View {
        List {
            ForEach(visibleEntries) { entry in
                if entry.isDirectory {
                    NavigationLink {
                        FolderView(session: session, share: share, path: entry.path)
                    } label: {
                        EntryRow(entry: entry, historyEntry: nil, isPreparing: false)
                    }
                } else {
                    Button {
                        play(entry, fromStart: false)
                    } label: {
                        EntryRow(entry: entry,
                                 historyEntry: history.entry(for: key(for: entry)),
                                 isPreparing: preparingID == entry.id)
                    }
                    .disabled(!entry.kind.isPlayable)
                    .contextMenu { contextMenu(for: entry) }
                    .swipeActions(edge: .trailing) {
                        if history.entry(for: key(for: entry)) != nil {
                            Button {
                                history.remove(key: key(for: entry))
                            } label: {
                                Label("Olvidar", systemImage: "arrow.counterclockwise")
                            }
                            .tint(.gray)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if loading && entries.isEmpty {
                ProgressView()
            } else if let errorText {
                MessageStateView(symbol: "exclamationmark.triangle", title: "No se pudo abrir la carpeta",
                                 message: errorText, actionTitle: "Reintentar") {
                    Task { await load() }
                }
            } else if visibleEntries.isEmpty {
                MessageStateView(symbol: "film.stack",
                                 title: query.isEmpty ? "Carpeta sin videos" : "Sin resultados",
                                 message: query.isEmpty && !showAllFiles ? "Activa «Mostrar todos los archivos» para ver el resto." : nil)
            }
        }
        .navigationTitle(title)
        .searchable(text: $query, prompt: "Buscar en esta carpeta")
        .refreshable { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Ordenar", selection: $sortRaw) {
                        ForEach(BrowserSort.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    Toggle("Mostrar todos los archivos", isOn: $showAllFiles)
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
            }
        }
        .task {
            if entries.isEmpty { await load() }
        }
    }

    @ViewBuilder
    private func contextMenu(for entry: SMBEntry) -> some View {
        Button {
            play(entry, fromStart: false)
        } label: {
            Label("Reproducir", systemImage: "play.fill")
        }
        if PlaybackHistory.shared.resumePosition(for: key(for: entry)) != nil {
            Button {
                play(entry, fromStart: true)
            } label: {
                Label("Reproducir desde el inicio", systemImage: "backward.end.fill")
            }
        }
        Button {
            history.markFinishedOrInsert(key: key(for: entry), title: entry.name,
                                         source: .smb(serverID: session.server.id, share: share, path: entry.path))
        } label: {
            Label("Marcar como visto", systemImage: "checkmark.circle")
        }
        Button {
            UIPasteboard.general.string = "smb://\(session.server.cleanHost)/\(share)/\(entry.path)"
        } label: {
            Label("Copiar ruta", systemImage: "doc.on.doc")
        }
    }

    private func key(for entry: SMBEntry) -> String {
        PlaybackRouter.historyKey(for: .smb(serverID: session.server.id, share: share, path: entry.path),
                                  fallbackURL: URL(fileURLWithPath: "/"))
    }

    private func load() async {
        loading = true
        errorText = nil
        do {
            entries = try await session.contents(share: share, path: path)
        } catch {
            errorText = SMBError.friendly(error)
        }
        loading = false
    }

    private func play(_ entry: SMBEntry, fromStart: Bool) {
        guard entry.kind.isPlayable, preparingID == nil else { return }
        preparingID = entry.id
        let server = session.server
        let snapshot = entries
        Task {
            let subtitles = await SubtitleFetcher.siblings(for: entry, in: snapshot, session: session, share: share)
            let password = ServerStore.shared.password(for: server)
            preparingID = nil
            guard let url = server.playbackURL(share: share, path: entry.path, password: password) else {
                PlaybackRouter.shared.alertMessage = "No se pudo construir la dirección del archivo."
                return
            }
            let source = PlaybackSource.smb(serverID: server.id, share: share, path: entry.path)
            var request = PlayRequest(url: url, title: entry.name, historyKey: key(for: entry), source: source)
            request.subtitleFiles = subtitles
            request.workgroup = server.domain
            request.forceStartAtZero = fromStart
            PlaybackRouter.shared.play(request)
        }
    }
}

struct EntryRow: View {
    let entry: SMBEntry
    let historyEntry: HistoryEntry?
    let isPreparing: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: entry.isDirectory ? "folder.fill" : entry.kind.symbol)
                .font(.title3)
                .foregroundStyle(entry.isDirectory ? Color.accentColor : (entry.kind.isPlayable ? Color.primary : Color.secondary))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .lineLimit(2)
                    .foregroundStyle(entry.isDirectory || entry.kind.isPlayable ? Color.primary : Color.secondary)
                if !entry.isDirectory {
                    HStack(spacing: 8) {
                        Text(Formatters.bytes(entry.size))
                        if let date = entry.modified {
                            Text(Formatters.shortDate.string(from: date))
                        }
                        if let historyEntry, !historyEntry.isFinished, historyEntry.position > 15 {
                            Text("\(Formatters.time(historyEntry.position)) / \(Formatters.time(historyEntry.duration))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let historyEntry, !historyEntry.isFinished, historyEntry.position > 15 {
                        WatchProgressBar(progress: historyEntry.progress)
                            .frame(maxWidth: 240)
                    }
                }
            }

            Spacer(minLength: 8)

            if isPreparing {
                ProgressView()
            } else if let historyEntry, historyEntry.isFinished {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Visto")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
