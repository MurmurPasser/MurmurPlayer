import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var history: PlaybackHistory

    @AppStorage(PlayerSettings.Keys.engine) private var engine = PlaybackEngine.auto.rawValue
    @AppStorage(PlayerSettings.Keys.hardwareDecode) private var hardwareDecode = true
    @AppStorage(PlayerSettings.Keys.forceSDR) private var forceSDR = false
    @AppStorage(PlayerSettings.Keys.autoPiP) private var autoPiP = true
    @AppStorage(PlayerSettings.Keys.backgroundAudio) private var backgroundAudio = false
    @AppStorage(PlayerSettings.Keys.buffer) private var buffer = BufferProfile.large.rawValue
    @AppStorage(PlayerSettings.Keys.resume) private var resume = true
    @AppStorage(PlayerSettings.Keys.accurateSeek) private var accurateSeek = false
    @AppStorage(PlayerSettings.Keys.audioLanguage) private var audioLanguage = AudioLanguage.none.rawValue
    @AppStorage(PlayerSettings.Keys.autoSubtitles) private var autoSubtitles = true
    @AppStorage(PlayerSettings.Keys.showAllFiles) private var showAllFiles = false

    @State private var confirmClear = false

    private var selectedEngine: PlaybackEngine {
        PlaybackEngine(rawValue: engine) ?? .auto
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Picker("Motor", selection: $engine) {
                    ForEach(PlaybackEngine.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                Toggle("Decodificación por hardware", isOn: $hardwareDecode)
                Toggle("Forzar SDR", isOn: $forceSDR)
            } header: {
                Text("Motor de reproducción")
            } footer: {
                Text("\(selectedEngine.detail) Los archivos del NAS (smb://) siempre usan FFmpeg. Desactiva el hardware solo si ves artefactos: por software gasta más batería y puede no llegar a 4K HEVC.")
            }

            Section {
                Toggle("PiP automático al salir de la app", isOn: $autoPiP)
                Toggle("Seguir sonando en segundo plano", isOn: $backgroundAudio)
            } header: {
                Text("Picture in Picture")
            } footer: {
                Text("Con PiP automático, al ir a la pantalla de inicio el video sigue flotando. «Segundo plano» mantiene solo el audio si no usas PiP (útil para conciertos o podcasts).")
            }

            Section {
                Picker("Búfer", selection: $buffer) {
                    ForEach(BufferProfile.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
            } header: {
                Text("Red")
            } footer: {
                Text("Un búfer mayor evita cortes con Wi-Fi inestable o remuxes 4K de alto bitrate, a cambio de usar más memoria.")
            }

            Section {
                Toggle("Reanudar donde lo dejé", isOn: $resume)
                Toggle("Búsqueda precisa", isOn: $accurateSeek)
                Picker("Idioma de audio preferido", selection: $audioLanguage) {
                    ForEach(AudioLanguage.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                Toggle("Activar subtítulos automáticamente", isOn: $autoSubtitles)
            } header: {
                Text("Reproducción")
            } footer: {
                Text("La búsqueda precisa salta al fotograma exacto, pero es más lenta en archivos grandes.")
            }

            Section("Navegador") {
                Toggle("Mostrar todos los archivos", isOn: $showAllFiles)
            }

            Section {
                Button("Borrar historial de reproducción", role: .destructive) {
                    confirmClear = true
                }
                .disabled(history.entries.isEmpty)
            }

            Section {
                LabeledContent("Versión", value: version)
                LabeledContent("Motor", value: "KSPlayer + FFmpeg")
                LabeledContent("Cliente SMB", value: "AMSMB2 (libsmb2)")
            } header: {
                Text("Acerca de")
            } footer: {
                Text("Murmur Player usa KSPlayer (GPL-3.0), FFmpeg y AMSMB2 (LGPL-2.1).")
            }
        }
        .navigationTitle("Ajustes")
        .confirmationDialog("¿Borrar todo el historial?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Borrar historial", role: .destructive) { history.clear() }
        }
        .onChange(of: backgroundAudio) { _ in PlayerSettings.applyGlobalDefaults() }
        .onChange(of: autoPiP) { _ in PlayerSettings.applyGlobalDefaults() }
    }
}
