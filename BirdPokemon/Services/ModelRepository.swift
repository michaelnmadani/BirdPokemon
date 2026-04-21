import Foundation
import CoreML
import FirebaseStorage

/// Resolves a compiled Core ML model URL for a given region.
///
/// Lookup order:
///   1. Bundled compiled model  (`BirdClassifier_<REGION>.mlmodelc`)
///   2. Bundled source model    (`BirdClassifier_<REGION>.mlmodel`, compiled on first use)
///   3. On-device cache         (previously downloaded + compiled)
///   4. Firebase Storage        (`models/BirdClassifier_<REGION>.mlmodel`, then compile + cache)
///
/// Only region AU ships bundled per the plan. NZ / GB / US are fetched from
/// Storage the first time that region is selected, then reused from the cache
/// on subsequent launches.
actor ModelRepository {
    static let shared = ModelRepository()

    enum ModelError: Error, LocalizedError {
        case compilationFailed(underlying: Error)
        case downloadFailed(underlying: Error)
        case ioFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .compilationFailed(let e): return "Couldn't prepare the model: \(e.localizedDescription)"
            case .downloadFailed(let e):    return "Couldn't download the model: \(e.localizedDescription)"
            case .ioFailed(let e):          return "Couldn't save the model: \(e.localizedDescription)"
            }
        }
    }

    /// Progress for an in-flight download, 0…1. `nil` when not downloading.
    private(set) var downloadFraction: Double?

    /// Observers notified on download progress. Keyed by an opaque UUID so
    /// callers can remove themselves. Called on the actor; callers hop as needed.
    private var progressObservers: [UUID: (Double) -> Void] = [:]

    private let fileManager = FileManager.default

    func compiledModelURL(for region: Region) async throws -> URL {
        if let bundled = bundledCompiledURL(for: region) { return bundled }
        if let bundledSource = bundledSourceURL(for: region) {
            return try compileIfNeeded(sourceURL: bundledSource, region: region, copyIntoCache: false)
        }
        if let cached = cachedCompiledURL(for: region), fileManager.fileExists(atPath: cached.path) {
            return cached
        }
        let sourceURL = try await downloadModel(region: region)
        return try compileIfNeeded(sourceURL: sourceURL, region: region, copyIntoCache: true)
    }

    func addProgressObserver(_ block: @escaping (Double) -> Void) -> UUID {
        let id = UUID()
        progressObservers[id] = block
        return id
    }

    func removeProgressObserver(_ id: UUID) {
        progressObservers.removeValue(forKey: id)
    }

    private func bundledCompiledURL(for region: Region) -> URL? {
        Bundle.main.url(forResource: "BirdClassifier_\(region.rawValue)", withExtension: "mlmodelc")
    }

    private func bundledSourceURL(for region: Region) -> URL? {
        Bundle.main.url(forResource: "BirdClassifier_\(region.rawValue)", withExtension: "mlmodel")
    }

    private func cachedCompiledURL(for region: Region) -> URL? {
        modelsDir()?.appendingPathComponent("BirdClassifier_\(region.rawValue).mlmodelc")
    }

    private func cachedSourceURL(for region: Region) -> URL? {
        modelsDir()?.appendingPathComponent("BirdClassifier_\(region.rawValue).mlmodel")
    }

    private func modelsDir() -> URL? {
        guard let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = appSupport.appendingPathComponent("Models", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func downloadModel(region: Region) async throws -> URL {
        guard let destination = cachedSourceURL(for: region) else {
            throw ModelError.ioFailed(
                underlying: NSError(domain: "ModelRepository", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "No cache directory"])
            )
        }

        let ref = FirebaseService.storage.reference()
            .child("models/BirdClassifier_\(region.rawValue).mlmodel")

        notifyProgress(0)
        do {
            let url = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                let task = ref.write(toFile: destination)
                task.observe(.progress) { [weak self] snapshot in
                    guard let self, let progress = snapshot.progress else { return }
                    let fraction = progress.totalUnitCount > 0
                        ? Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                        : 0
                    Task { await self.notifyProgress(fraction) }
                }
                task.observe(.success) { _ in
                    cont.resume(returning: destination)
                }
                task.observe(.failure) { snapshot in
                    cont.resume(throwing: snapshot.error ?? NSError(domain: "ModelRepository", code: -2))
                }
            }
            notifyProgress(1)
            downloadFraction = nil
            return url
        } catch {
            downloadFraction = nil
            throw ModelError.downloadFailed(underlying: error)
        }
    }

    private func compileIfNeeded(sourceURL: URL, region: Region, copyIntoCache: Bool) throws -> URL {
        let compiled: URL
        do {
            compiled = try MLModel.compileModel(at: sourceURL)
        } catch {
            throw ModelError.compilationFailed(underlying: error)
        }

        guard copyIntoCache, let destination = cachedCompiledURL(for: region) else {
            return compiled
        }

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: compiled, to: destination)
            return destination
        } catch {
            throw ModelError.ioFailed(underlying: error)
        }
    }

    private func notifyProgress(_ fraction: Double) {
        downloadFraction = fraction
        for block in progressObservers.values {
            block(fraction)
        }
    }
}
