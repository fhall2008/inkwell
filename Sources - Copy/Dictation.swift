import AVFoundation
import Speech

/// Live speech to text using Apple's Speech framework.
@MainActor
final class Dictation: ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var errorText: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()

    func start() {
        guard !isListening else { return }
        transcript = ""
        errorText = nil
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.errorText = "Allow Speech Recognition for Inkwell in Settings."
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.errorText = "Allow Microphone access for Inkwell in Settings."
                            return
                        }
                        self.begin()
                    }
                }
            }
        }
    }

    /// Stops listening but keeps the transcript so far.
    func stop() {
        guard isListening else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Stops and throws the transcript away.
    func cancel() {
        task?.cancel()
        stop()
        transcript = ""
        errorText = nil
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else {
            errorText = "Speech recognition isn't available right now."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req

            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.tap(req))
            engine.prepare()
            try engine.start()
            isListening = true

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let finished = error != nil || (result?.isFinal ?? false)
                Task { @MainActor in
                    guard let self else { return }
                    if let text, self.isListening { self.transcript = text }
                    if finished { self.stop() }
                }
            }
        } catch {
            errorText = "Couldn't start the microphone."
            stop()
        }
    }

    // Built outside the main actor because the audio engine calls it on its own thread.
    private nonisolated static func tap(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }
}
