import KSPlayer
import SwiftUI

/// Estado mutable que no debe redibujar la vista (se actualiza varias veces por segundo).
private final class ProgressTracker {
    var position: Double = 0
    var duration: Double = 0
    var lastCommit = Date.distantPast
    var audioPreferenceAttempts = 0
    var audioPreferenceDone = false
}

struct PlayerScreen: View {
    let request: PlayRequest

    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @State private var options: KSOptions
    @State private var subtitleSource: SubtitleDataSouce?
    @State private var tracker = ProgressTracker()
    @State private var errorMessage: String?
    @State private var resumeBanner: String?

    init(request: PlayRequest) {
        self.request = request
        let options = PlayerSettings.makeOptions(for: request)
        var banner: String?
        if !request.forceStartAtZero, PlayerSettings.resumeEnabled,
           let position = PlaybackHistory.shared.resumePosition(for: request.historyKey)
        {
            options.startPlayTime = position
            banner = "Reanudando en \(Formatters.time(position))"
        }
        _options = State(initialValue: options)
        _resumeBanner = State(initialValue: banner)
        _subtitleSource = State(initialValue: request.subtitleFiles.isEmpty ? nil : URLSubtitleDataSouce(urls: request.subtitleFiles))
    }

    var body: some View {
        KSVideoPlayerView(coordinator: coordinator,
                          url: request.url,
                          options: options,
                          title: request.title,
                          subtitleDataSouce: subtitleSource)
            .overlay(alignment: .top) {
                if let resumeBanner {
                    Text(resumeBanner)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .statusBarHidden()
            .onAppear(perform: attachCallbacks)
            .onDisappear(perform: tearDown)
            .task {
                guard resumeBanner != nil else { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation { resumeBanner = nil }
            }
            .alert("No se pudo reproducir", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Cerrar", role: .cancel) { PlaybackRouter.shared.current = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func attachCallbacks() {
        let tracker = self.tracker
        let request = self.request
        let playerCoordinator = coordinator
        playerCoordinator.onPlay = { [weak playerCoordinator] current, total in
            guard current.isFinite, total.isFinite, total > 0 else { return }
            tracker.position = current
            tracker.duration = total
            if Date().timeIntervalSince(tracker.lastCommit) > 10 {
                tracker.lastCommit = Date()
                PlaybackHistory.shared.record(key: request.historyKey, title: request.title,
                                              source: request.source, position: current, duration: total)
            }
            if !tracker.audioPreferenceDone, let player = playerCoordinator?.playerLayer?.player {
                Self.applyAudioPreference(player: player, tracker: tracker)
            }
        }
        playerCoordinator.onFinish = { _, error in
            if let error {
                errorMessage = Self.describe(error, url: request.url)
            } else {
                PlaybackHistory.shared.markFinished(key: request.historyKey)
            }
        }
    }

    private func tearDown() {
        if tracker.duration > 0 {
            PlaybackHistory.shared.record(key: request.historyKey, title: request.title,
                                          source: request.source, position: tracker.position,
                                          duration: tracker.duration)
        }
        request.securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    /// Selecciona la pista de audio en el idioma preferido (una sola vez por video).
    private static func applyAudioPreference(player: MediaPlayerProtocol, tracker: ProgressTracker) {
        let language = PlayerSettings.audioLanguage
        guard language != .none else {
            tracker.audioPreferenceDone = true
            return
        }
        let tracks = player.tracks(mediaType: .audio)
        guard !tracks.isEmpty else {
            tracker.audioPreferenceAttempts += 1
            if tracker.audioPreferenceAttempts > 40 { tracker.audioPreferenceDone = true }
            return
        }
        tracker.audioPreferenceDone = true
        if let current = tracks.first(where: { $0.isEnabled }),
           language.matches(languageCode: current.languageCode, name: current.name)
        {
            return
        }
        if let match = tracks.first(where: { language.matches(languageCode: $0.languageCode, name: $0.name) }) {
            player.select(track: match)
        }
    }

    private static func describe(_ error: Error, url: URL) -> String {
        var message = error.localizedDescription
        if url.scheme?.lowercased() == "smb" {
            message += "\n\nSi es un archivo del NAS, revisa que el usuario tenga permiso de lectura y que el servidor permita SMB2/3."
        } else if PlayerSettings.engine == .avplayer {
            message += "\n\nEl motor está en «Solo AVPlayer». Cámbialo a «Automático» en Ajustes para abrir MKV, DTS o AVI."
        }
        return message
    }
}
