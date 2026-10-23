import SwiftUI
import UniformTypeIdentifiers

/// "Identify by sound": listen through the microphone (or analyse a
/// recording) with BirdNET and list the birds heard, ready to log.
@MainActor
final class ListenViewModel: ObservableObject {
    enum Mode: Equatable {
        case idle, loading, listening
        case analysing(progress: Double)
    }

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var tally: [Int: SoundTallyEntry] = [:]
    @Published private(set) var windowsDone = 0
    @Published private(set) var source: String?
    @Published var fieldGuideOnly = true
    @Published var errorMessage: String?

    /// Loaded once and kept for the app's lifetime (the model is ~50 MB).
    private static var sharedIdentifier: SoundIdentifier?
    private(set) var identifier: SoundIdentifier?
    private var listener: AudioListener?

    var isBusy: Bool {
        switch mode {
        case .loading, .analysing: return true
        case .idle, .listening: return false
        }
    }

    /// Birds heard, best first, honouring the field-guide filter.
    var results: [SoundTallyEntry] {
        guard let identifier else { return [] }
        return SoundIDCore.rank(tally).filter { !fieldGuideOnly || identifier.codes[$0.index] != nil }
    }

    /// Birds heard that the field-guide filter is hiding.
    var hiddenCount: Int {
        guard fieldGuideOnly, let identifier else { return 0 }
        return tally.keys.filter { identifier.codes[$0] == nil }.count
    }

    func startListening(species: [Species]) async {
        do {
            let identifier = try await load(species: species)
            begin(source: nil)
            let listener = AudioListener()
            self.listener = listener
            try await listener.start { [weak self] samples, at in
                await self?.process(samples, at: at, with: identifier)
            }
            mode = .listening
        } catch {
            stopListening()
            mode = .idle
            errorMessage = error.localizedDescription
        }
    }

    func stopListening() {
        listener?.stop()
        listener = nil
        if mode == .listening { mode = .idle }
    }

    func analyse(fileAt url: URL, species: [Species]) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let identifier = try await load(species: species)
            begin(source: url.lastPathComponent)
            mode = .analysing(progress: 0)
            let samples = try await Task.detached(priority: .userInitiated) { try SoundIdentifier.decode(url: url) }.value
            let chunks = SoundIDCore.windows(samples)
            for (i, chunk) in chunks.enumerated() {
                await process(chunk.samples, at: Double(chunk.start) / SoundIDCore.sampleRate, with: identifier)
                mode = .analysing(progress: Double(i + 1) / Double(chunks.count))
            }
            mode = .idle
            if tally.isEmpty { errorMessage = "No birds recognised in that recording." }
        } catch {
            mode = .idle
            errorMessage = "Couldn't analyse that recording: \(error.localizedDescription)"
        }
    }

    private func load(species: [Species]) async throws -> SoundIdentifier {
        if let identifier = identifier ?? Self.sharedIdentifier {
            self.identifier = identifier
            return identifier
        }
        mode = .loading
        let loaded = try await Task.detached(priority: .userInitiated) { try SoundIdentifier(species: species) }.value
        Self.sharedIdentifier = loaded
        identifier = loaded
        return loaded
    }

    private func begin(source: String?) {
        tally = [:]
        windowsDone = 0
        errorMessage = nil
        self.source = source
    }

    private func process(_ samples: [Float], at seconds: Double, with identifier: SoundIdentifier) async {
        do {
            let logits = try await identifier.classify(samples)
            // Tally every bird; the field-guide filter applies when showing results.
            let labels = identifier.labels
            SoundIDCore.addToTally(&tally, SoundIDCore.detections(logits) { labels[$0].isBird }, at: seconds)
            windowsDone += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ListenView: View {
    /// Log a sighting of `species`, heard with `confidence`.
    let onLog: (Species, Double) -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var catalog: SpeciesCatalog
    @EnvironmentObject private var store: SightingStore
    @StateObject private var model = ListenViewModel()
    @State private var showImporter = false

    var body: some View {
        List {
            Section {
                Text("Hold your phone towards the bird and listen, or analyse a recording. BirdNET runs on your phone — audio is never uploaded or saved.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if model.mode == .listening {
                    Button(role: .destructive) {
                        model.stopListening()
                    } label: {
                        Label("Stop listening", systemImage: "stop.circle.fill")
                    }
                } else {
                    Button {
                        Task { await model.startListening(species: catalogSpecies) }
                    } label: {
                        Label("Start listening", systemImage: "mic.fill")
                    }
                    .disabled(model.isBusy)
                }

                Button {
                    showImporter = true
                } label: {
                    Label("Analyse a recording", systemImage: "waveform")
                }
                .disabled(model.isBusy || model.mode == .listening)

                Toggle("Only birds in the field guide", isOn: $model.fieldGuideOnly)
            } footer: {
                Text("Sound ID by BirdNET (Cornell Lab of Ornithology & Chemnitz University of Technology).")
            }

            Section {
                status
                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }

            if !model.results.isEmpty {
                Section("Heard") {
                    ForEach(model.results, id: \.index) { entry in
                        row(entry)
                    }
                }
            } else if model.hiddenCount > 0 {
                Section {
                    Text("No field-guide birds heard. \(model.hiddenCount) other \(model.hiddenCount == 1 ? "bird" : "birds") — turn off “Only birds in the field guide” to see \(model.hiddenCount == 1 ? "it" : "them").")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Identify by sound")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result {
                Task { await model.analyse(fileAt: url, species: catalogSpecies) }
            }
        }
        .onDisappear { model.stopListening() }
    }

    private var catalogSpecies: [Species] {
        catalog.species(in: appState.selectedRegion)
    }

    @ViewBuilder
    private var status: some View {
        switch model.mode {
        case .loading:
            HStack { ProgressView(); Text("Loading BirdNET…").foregroundStyle(.secondary) }
        case .listening:
            Label("Listening… \(model.windowsDone * 3)s analysed", systemImage: "waveform")
                .symbolEffect(.variableColor.iterative)
                .foregroundStyle(Color.accentColor)
        case .analysing(let progress):
            ProgressView(value: progress) {
                Text("Analysing \(model.source ?? "recording")…")
            }
        case .idle:
            if model.windowsDone > 0 {
                Text("\(model.windowsDone * 3)s of audio analysed\(model.source.map { " from \($0)" } ?? "").")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Nothing analysed yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: SoundTallyEntry) -> some View {
        if let identifier = model.identifier {
            let label = identifier.labels[entry.index]
            let species = identifier.codes[entry.index].flatMap { catalog.species(code: $0) }
            let percent = Int((entry.best * 100).rounded())
            HStack(spacing: 12) {
                AsyncRemoteImage(url: catalog.picture(for: species))
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        if let species, store.isCaptured(species) {
                            CapturedBadgeView().offset(x: 6, y: -6)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(species?.commonName ?? label.commonName).font(.body.weight(.medium))
                    Text(label.scientificName).font(.footnote).italic().foregroundStyle(.secondary)
                    Text("\(percent)% · heard \(entry.count)× · at \(Self.timestamp(entry.lastAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if species == nil {
                        Text("Not in the field guide").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let species {
                    Button("Log it") { onLog(species, entry.best) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }

    static func timestamp(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
