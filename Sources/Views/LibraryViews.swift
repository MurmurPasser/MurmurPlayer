import UIKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Continuar viendo

struct RecentsView: View {
    @EnvironmentObject private var history: PlaybackHistory
    @EnvironmentObject private var router: PlaybackRouter
    @State private var confirmClear = false

    private var inProgress: [HistoryEntry] {
        history.recent.filter { !$0.isFinished && $0.position > 15 }
    }

    private var watched: [HistoryEntry] {
        history.recent.filter { $0.isFinished && $0.duration > 1 }.prefix(30).map { $0 }
    }

    var body: some View {
        List {
            if !inProgress.isEmpty {
                Section("En progreso") {
                    ForEach(inProgress) { entry in
                        row(entry)
                    }
                }
            }
            if !watched.isEmpty {
                Section("Vistos recientemente") {
                    ForEach(watched) { entry in
                        row(entry)
                    }
                }
            }
        }
        .overlay {
            if inProgress.isEmpty && watched.isEmpty {
                MessageStateView(symbol: "play.rectangle.on.rectangle",
                                 title: "Nada por aquí todavía",
                                 message: "Añade tu NAS en «Servidores» o abre un archivo. Lo que veas aparecerá aquí para retomarlo donde quedaste.")
            }
        }
        .navigationTitle("Continuar viendo")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(history.entries.isEmpty)
            }
        }
        .confirmationDialog("¿Borrar todo el historial?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Borrar historial", role: .destructive) { history.clear() }
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        Button {
            router.resume(entry, fromStart: entry.isFinished)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon(for: entry.source))
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.title)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text(subtitle(for: entry))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !entry.isFinished {
                        WatchProgressBar(progress: entry.progress)
                            .frame(maxWidth: 280)
                    }
                }
                Spacer()
                Image(systemName: entry.isFinished ? "arrow.counterclockwise.circle" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.vertical, 4)
        }
        .contextMenu {
            if !entry.isFinished {
                Button {
                    router.resume(entry, fromStart: true)
                } label: {
                    Label("Desde el inicio", systemImage: "backward.end.fill")
                }
            }
            Button(role: .destructive) {
                history.remove(key: entry.key)
            } label: {
                Label("Quitar", systemImage: "minus.circle")
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                history.remove(key: entry.key)
            } label: {
                Label("Quitar", systemImage: "trash")
            }
        }
    }

    private func icon(for source: PlaybackSource) -> String {
        switch source {
        case .smb: return "server.rack"
        case .documents: return "ipad.landscape"
        case .bookmark: return "folder"
        case .remote: return "globe"
        }
    }

    private func subtitle(for entry: HistoryEntry) -> String {
        let when = Formatters.relativeDate.localizedString(for: entry.updatedAt, relativeTo: Date())
        if entry.isFinished { return "Visto · \(when)" }
        let remaining = max(0, entry.duration - entry.position)
        return "Quedan \(Formatters.time(remaining)) · \(when)"
    }
}

// MARK: - En este iPad

struct LocalLibraryView: View {
    @EnvironmentObject private var history: PlaybackHistory
    @EnvironmentObject private var router: PlaybackRouter
    @State private var files: [URL] = []
    @State private var showImporter = false

    var body: some View {
        List {
            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("Abrir desde Archivos…", systemImage: "folder.badge.plus")
                }
            } footer: {
                Text("Incluye iCloud, discos USB y servidores que hayas añadido en Archivos con «Conectarse al servidor».")
            }

            Section {
                if files.isEmpty {
                    Text("Copia videos a Archivos › En mi iPad › Murmur Player y aparecerán aquí.")
                        .foregroundStyle(.secondary)
                }
                ForEach(files, id: \.self) { url in
                    Button {
                        router.playLocalFile(url, needsSecurityScope: false)
                    } label: {
                        localRow(url)
                    }
                }
                .onDelete(perform: delete)
            } header: {
                Text("Documentos de la app")
            }
        }
        .navigationTitle("En este iPad")
        .refreshable { reload() }
        .onAppear(perform: reload)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.movie, .audio, .audiovisualContent, .item]) { result in
            if case let .success(url) = result {
                router.playLocalFile(url, needsSecurityScope: true)
            }
        }
    }

    private func localRow(_ url: URL) -> some View {
        let relative = LocalFiles.relativePath(of: url) ?? url.lastPathComponent
        let entry = history.entry(for: "docs://\(relative)")
        return HStack(spacing: 14) {
            Image(systemName: MediaKind(fileName: url.lastPathComponent).symbol)
                .font(.title3)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(url.lastPathComponent).lineLimit(2).foregroundStyle(.primary)
                if let entry, !entry.isFinished, entry.position > 15 {
                    WatchProgressBar(progress: entry.progress).frame(maxWidth: 240)
                }
            }
            Spacer()
            if let entry, entry.isFinished {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }

    private func reload() {
        files = LocalFiles.listDocuments()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            try? FileManager.default.removeItem(at: files[index])
        }
        reload()
    }
}

// MARK: - Abrir URL

struct OpenURLView: View {
    @EnvironmentObject private var router: PlaybackRouter
    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsedURL: URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              ["http", "https", "smb", "rtsp", "rtmp", "ftp", "nfs"].contains(scheme)
        else { return nil }
        return url
    }

    var body: some View {
        Form {
            Section {
                TextField("https://… · smb://usuario:clave@nas/video/peli.mkv · rtsp://…", text: $text)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit(play)
                Button("Reproducir", action: play)
                    .disabled(parsedURL == nil)
            } footer: {
                Text("Sirve para streams HTTP/HLS, cámaras RTSP, Jellyfin/Plex en modo directo o una ruta SMB escrita a mano.")
            }
            Section {
                Button("Pegar del portapapeles") {
                    if let string = UIPasteboard.general.string { text = string }
                }
            }
        }
        .navigationTitle("Abrir URL")
        .onAppear { focused = true }
    }

    private func play() {
        guard let url = parsedURL else { return }
        router.playRemote(url)
    }
}
