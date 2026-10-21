import Foundation
import AVFoundation
import TensorFlowLiteC

/// BirdNET V2.4 sound identification, on device with TensorFlow Lite.
///
/// The model and labels are bundled when `scripts/birdnet/fetch-model.sh` has
/// been run before generating the project (CI always does). BirdNET: K. Lisa
/// Yang Center for Conservation Bioacoustics, Cornell Lab of Ornithology &
/// Chemnitz University of Technology — model licensed CC BY-NC-SA 4.0.
actor SoundIdentifier {
    enum SoundIDError: LocalizedError {
        case notBundled
        case modelFailed(String)
        case tooLong

        var errorDescription: String? {
            switch self {
            case .notBundled: return "Sound identification isn't included in this build."
            case .modelFailed(let step): return "The BirdNET model couldn't run (\(step))."
            case .tooLong: return "Recordings longer than 10 minutes aren't supported."
            }
        }
    }

    static let modelName = "BirdNET_GLOBAL_6K_V2.4_Model_FP32"
    static let labelsName = "BirdNET_GLOBAL_6K_V2.4_Labels"
    static let maxFileSeconds = 10.0 * 60

    static var isAvailable: Bool {
        Bundle.main.url(forResource: modelName, withExtension: "tflite") != nil
            && Bundle.main.url(forResource: labelsName, withExtension: "txt") != nil
    }

    nonisolated let labels: [SoundLabel]
    /// Field-guide species code for each class (nil if not in the guide).
    nonisolated let codes: [String?]
    private let interpreter: TFLiteInterpreter

    /// Loads the model (about a second); call off the main thread.
    init(species: [Species], bundle: Bundle = .main) throws {
        guard let modelURL = bundle.url(forResource: Self.modelName, withExtension: "tflite"),
              let labelsURL = bundle.url(forResource: Self.labelsName, withExtension: "txt") else {
            throw SoundIDError.notBundled
        }
        let labels = SoundIDCore.parseLabels(try String(contentsOf: labelsURL, encoding: .utf8))
        self.labels = labels
        self.codes = SoundIDCore.mapLabels(labels, to: species)
        self.interpreter = try TFLiteInterpreter(modelPath: modelURL.path, outputCount: labels.count)
    }

    /// One 3-second, 48 kHz mono window → raw logits, one per class.
    func classify(_ samples: [Float]) throws -> [Float] {
        try interpreter.run(samples)
    }

    /// Decode an audio file to 48 kHz mono.
    static func decode(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat // deinterleaved Float32
        guard Double(file.length) / format.sampleRate <= maxFileSeconds else { throw SoundIDError.tooLong }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw SoundIDError.modelFailed("audio buffer")
        }
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData else { throw SoundIDError.modelFailed("audio format") }
        let frames = Int(buffer.frameLength)
        let channels = (0..<Int(format.channelCount)).map { Array(UnsafeBufferPointer(start: data[$0], count: frames)) }
        return SoundIDCore.resample(SoundIDCore.mixToMono(channels), from: format.sampleRate)
    }
}

/// Minimal wrapper over the TensorFlow Lite C API for a model with one float
/// input and one float output. Not thread-safe: `SoundIdentifier` serialises use.
final class TFLiteInterpreter {
    private let model: OpaquePointer
    private let options: OpaquePointer
    private let interpreter: OpaquePointer
    private let outputCount: Int

    init(modelPath: String, outputCount: Int, threads: Int32 = 2) throws {
        guard let model = TfLiteModelCreateFromFile(modelPath) else {
            throw SoundIdentifier.SoundIDError.modelFailed("load")
        }
        guard let options = TfLiteInterpreterOptionsCreate() else {
            TfLiteModelDelete(model)
            throw SoundIdentifier.SoundIDError.modelFailed("options")
        }
        TfLiteInterpreterOptionsSetNumThreads(options, threads)
        guard let interpreter = TfLiteInterpreterCreate(model, options) else {
            TfLiteInterpreterOptionsDelete(options)
            TfLiteModelDelete(model)
            throw SoundIdentifier.SoundIDError.modelFailed("interpreter")
        }
        self.model = model
        self.options = options
        self.interpreter = interpreter
        self.outputCount = outputCount
        guard TfLiteInterpreterAllocateTensors(interpreter) == kTfLiteOk else {
            throw SoundIdentifier.SoundIDError.modelFailed("allocate")
        }
    }

    deinit {
        TfLiteInterpreterDelete(interpreter)
        TfLiteInterpreterOptionsDelete(options)
        TfLiteModelDelete(model)
    }

    func run(_ input: [Float]) throws -> [Float] {
        guard let inputTensor = TfLiteInterpreterGetInputTensor(interpreter, 0),
              TfLiteTensorByteSize(inputTensor) == input.count * MemoryLayout<Float>.stride else {
            throw SoundIdentifier.SoundIDError.modelFailed("input size")
        }
        let copied = input.withUnsafeBytes { TfLiteTensorCopyFromBuffer(inputTensor, $0.baseAddress, $0.count) }
        guard copied == kTfLiteOk else { throw SoundIdentifier.SoundIDError.modelFailed("input") }
        guard TfLiteInterpreterInvoke(interpreter) == kTfLiteOk else {
            throw SoundIdentifier.SoundIDError.modelFailed("invoke")
        }
        guard let outputTensor = TfLiteInterpreterGetOutputTensor(interpreter, 0),
              TfLiteTensorByteSize(outputTensor) == outputCount * MemoryLayout<Float>.stride else {
            throw SoundIdentifier.SoundIDError.modelFailed("output size")
        }
        var output = [Float](repeating: 0, count: outputCount)
        let status = output.withUnsafeMutableBytes { TfLiteTensorCopyToBuffer(outputTensor, $0.baseAddress, $0.count) }
        guard status == kTfLiteOk else { throw SoundIdentifier.SoundIDError.modelFailed("output") }
        return output
    }
}
