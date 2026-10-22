import Foundation
import Speech
import AVFoundation

/// 語音輸入（Speech framework）。持續把辨識結果寫到 transcript，由畫面合成到輸入框。
@MainActor
final class SpeechInput: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var error: String?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    private var tapInstalled = false

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func start() {
        error = nil
        let localeId = Language.isEnglish ? "en-US" : "zh-TW"
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async { self.error = Language.isEnglish ? "Speech recognition not authorized" : "未授權語音辨識" }
                return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                DispatchQueue.main.async {
                    guard ok else { self.error = Language.isEnglish ? "Microphone not authorized" : "未授權麥克風"; return }
                    self.begin()
                }
            }
        }
    }

    private func begin() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else {
                self.error = Language.isEnglish ? "No microphone input available" : "找不到可用的麥克風"
                return
            }
            if tapInstalled {
                input.removeTap(onBus: 0)
                tapInstalled = false
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                req.append(buffer)
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            isRecording = true
            transcript = ""

            task = recognizer?.recognitionTask(with: req) { [weak self] result, err in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    DispatchQueue.main.async { self.transcript = text }
                }
                if err != nil { DispatchQueue.main.async { self.stop() } }
            }
        } catch {
            self.error = error.localizedDescription
            stop()
        }
    }

    func stop() {
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
