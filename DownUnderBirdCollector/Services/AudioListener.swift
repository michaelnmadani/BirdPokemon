import Foundation
import AVFoundation

/// Taps the microphone and hands over every 3 seconds of audio, resampled to
/// 48 kHz mono, for BirdNET. Windows that arrive while the previous one is
/// still being classified are skipped rather than queued.
final class AudioListener {
    enum ListenerError: LocalizedError {
        case permissionDenied
        case noInput

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Microphone access is off. Allow it in Settings to identify birds by sound."
            case .noInput: return "No microphone is available."
            }
        }
    }

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "AudioListener")
    private var pending: [Float] = []
    private var elapsed = 0.0
    private var busy = false

    /// `onWindow(samples, startSeconds)` runs off the main thread.
    func start(onWindow: @escaping ([Float], Double) async -> Void) async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw ListenerError.permissionDenied }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw ListenerError.noInput }
        let rate = format.sampleRate
        let needed = Int(3 * rate)

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            self.queue.async { self.append(samples, needed: needed, rate: rate, onWindow: onWindow) }
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        queue.async {
            self.pending = []
            self.elapsed = 0
        }
    }

    // Runs on `queue`.
    private func append(_ samples: [Float], needed: Int, rate: Double, onWindow: @escaping ([Float], Double) async -> Void) {
        pending.append(contentsOf: samples)
        guard pending.count >= needed else { return }
        let chunk = Array(pending.prefix(needed))
        pending.removeFirst(needed)
        let startAt = elapsed
        elapsed += 3
        guard !busy else { return }
        busy = true
        Task.detached(priority: .userInitiated) {
            await onWindow(SoundIDCore.resample(chunk, from: rate), startAt)
            self.queue.async { self.busy = false }
        }
    }
}
