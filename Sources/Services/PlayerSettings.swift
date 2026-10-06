import Foundation
import KSPlayer

enum PlaybackEngine: String, CaseIterable, Identifiable {
    case auto, ffmpeg, avplayer
    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automático"
        case .ffmpeg: return "Siempre FFmpeg"
        case .avplayer: return "Solo AVPlayer"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "Intenta AVPlayer (nativo, menor consumo) y si el formato no es compatible pasa a FFmpeg."
        case .ffmpeg: return "Usa siempre el motor FFmpeg (como VLC). Abre casi todo: MKV, DTS, PGS, ASS."
        case .avplayer: return "Solo el reproductor de Apple. Máxima eficiencia, pero no abre MKV ni DTS."
        }
    }
}

enum BufferProfile: String, CaseIterable, Identifiable {
    case normal, large, huge
    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .large: return "Amplio (Wi-Fi)"
        case .huge: return "Máximo (4K remux)"
        }
    }

    var forward: Double {
        switch self {
        case .normal: return 3
        case .large: return 8
        case .huge: return 15
        }
    }

    var maximum: Double {
        switch self {
        case .normal: return 30
        case .large: return 60
        case .huge: return 120
        }
    }
}

enum AudioLanguage: String, CaseIterable, Identifiable {
    case none, es, en, ja, pt, fr, de, it
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Sin preferencia"
        case .es: return "Español"
        case .en: return "Inglés"
        case .ja: return "Japonés"
        case .pt: return "Portugués"
        case .fr: return "Francés"
        case .de: return "Alemán"
        case .it: return "Italiano"
        }
    }

    /// Códigos ISO 639-1 / 639-2 con los que suele venir etiquetada la pista.
    var codes: [String] {
        switch self {
        case .none: return []
        case .es: return ["es", "spa", "esl"]
        case .en: return ["en", "eng"]
        case .ja: return ["ja", "jpn"]
        case .pt: return ["pt", "por"]
        case .fr: return ["fr", "fra", "fre"]
        case .de: return ["de", "deu", "ger"]
        case .it: return ["it", "ita"]
        }
    }

    var nameHints: [String] {
        switch self {
        case .none: return []
        case .es: return ["español", "spanish", "castellano", "latino"]
        case .en: return ["english", "inglés"]
        case .ja: return ["japanese", "日本語"]
        case .pt: return ["portugu"]
        case .fr: return ["français", "french"]
        case .de: return ["deutsch", "german"]
        case .it: return ["italiano", "italian"]
        }
    }

    func matches(languageCode: String?, name: String) -> Bool {
        guard self != .none else { return false }
        if let code = languageCode?.lowercased(), codes.contains(where: { code == $0 || code.hasPrefix($0 + "-") || code.hasPrefix($0 + "_") }) {
            return true
        }
        let lowered = name.lowercased()
        return nameHints.contains { lowered.contains($0) }
    }
}

/// Ajustes persistidos (UserDefaults) y su traducción a KSOptions.
enum PlayerSettings {
    enum Keys {
        static let engine = "mp.engine"
        static let hardwareDecode = "mp.hardwareDecode"
        static let forceSDR = "mp.forceSDR"
        static let autoPiP = "mp.autoPiP"
        static let backgroundAudio = "mp.backgroundAudio"
        static let buffer = "mp.buffer"
        static let resume = "mp.resume"
        static let accurateSeek = "mp.accurateSeek"
        static let audioLanguage = "mp.audioLanguage"
        static let autoSubtitles = "mp.autoSubtitles"
        static let showAllFiles = "mp.showAllFiles"
        static let browserSort = "mp.browserSort"
    }

    private static var defaults: UserDefaults { .standard }

    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    static var engine: PlaybackEngine {
        PlaybackEngine(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .auto
    }

    static var buffer: BufferProfile {
        BufferProfile(rawValue: defaults.string(forKey: Keys.buffer) ?? "") ?? .large
    }

    static var audioLanguage: AudioLanguage {
        AudioLanguage(rawValue: defaults.string(forKey: Keys.audioLanguage) ?? "") ?? .none
    }

    static var hardwareDecode: Bool { bool(Keys.hardwareDecode, true) }
    static var forceSDR: Bool { bool(Keys.forceSDR, false) }
    static var autoPiP: Bool { bool(Keys.autoPiP, true) }
    static var backgroundAudio: Bool { bool(Keys.backgroundAudio, false) }
    static var resumeEnabled: Bool { bool(Keys.resume, true) }
    static var accurateSeek: Bool { bool(Keys.accurateSeek, false) }
    static var autoSubtitles: Bool { bool(Keys.autoSubtitles, true) }

    /// Valores globales que KSPlayer lee como estáticos.
    static func applyGlobalDefaults() {
        KSOptions.isPipPopViewController = false // al activar PiP la app pasa a segundo plano y el video flota
        KSOptions.canBackgroundPlay = backgroundAudio
        KSOptions.hardwareDecode = hardwareDecode
        KSOptions.isAccurateSeek = accurateSeek
        KSOptions.canStartPictureInPictureAutomaticallyFromInline = autoPiP
        KSOptions.preferredForwardBufferDuration = buffer.forward
        KSOptions.maxBufferDuration = buffer.maximum
        KSOptions.logLevel = .warning
    }

    /// Crea las opciones para una reproducción concreta y elige el motor.
    static func makeOptions(for request: PlayRequest) -> KSOptions {
        applyGlobalDefaults()

        let isSMB = request.url.scheme?.lowercased() == "smb"
        if isSMB || engine == .ffmpeg {
            // AVPlayer no sabe leer smb://, así que el NAS va directo a FFmpeg (que usa VideoToolbox si está activo).
            KSOptions.firstPlayerType = KSMEPlayer.self
            KSOptions.secondPlayerType = nil
        } else if engine == .avplayer {
            KSOptions.firstPlayerType = KSAVPlayer.self
            KSOptions.secondPlayerType = nil
        } else {
            KSOptions.firstPlayerType = KSAVPlayer.self
            KSOptions.secondPlayerType = KSMEPlayer.self
        }

        let options = KSOptions()
        options.hardwareDecode = hardwareDecode
        options.isAccurateSeek = accurateSeek
        options.preferredForwardBufferDuration = buffer.forward
        options.maxBufferDuration = buffer.maximum
        options.canStartPictureInPictureAutomaticallyFromInline = autoPiP
        options.autoSelectEmbedSubtitle = autoSubtitles
        if forceSDR {
            options.destinationDynamicRange = .sdr
        }
        if isSMB {
            let workgroup = request.workgroup.trimmingCharacters(in: .whitespaces)
            if !workgroup.isEmpty {
                options.formatContextOptions["workgroup"] = workgroup
            }
        }
        return options
    }
}
