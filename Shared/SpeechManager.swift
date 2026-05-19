import AVFoundation

// MARK: - SpeechManager

final class SpeechManager: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechManager()

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    func speakEnglish(word: String, example: String?) {
        stopIfSpeaking()
        let text = example.map { "\(word). \($0)" } ?? word
        speak(text: text, languageCode: "en-US", rate: 0.45)
    }

    func speakTurkish(meaning: String, exampleTurkish: String?) {
        stopIfSpeaking()
        let text = exampleTurkish.map { "\(meaning). \($0)" } ?? meaning
        speak(text: text, languageCode: "tr-TR", rate: 0.50)
    }

    // MARK: - Internal

    private func speak(text: String, languageCode: String, rate: Float) {
        configureAudioSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice   = AVSpeechSynthesisVoice(language: languageCode)
        utterance.rate    = rate
        utterance.pitchMultiplier = 1.05
        utterance.volume  = 1.0
        synthesizer.speak(utterance)
    }

    private func stopIfSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: .duckOthers
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
