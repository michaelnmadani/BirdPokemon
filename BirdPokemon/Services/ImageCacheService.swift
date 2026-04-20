import Foundation
import Nuke

enum ImageCacheService {
    /// Wire up Nuke with a disk cache tuned for bird thumbnails.
    static func configure() {
        let dataLoader: DataLoader = {
            let config = URLSessionConfiguration.default
            config.urlCache = URLCache(
                memoryCapacity: 20 * 1024 * 1024,
                diskCapacity: 200 * 1024 * 1024,
                diskPath: "birdpokemon-images"
            )
            return DataLoader(configuration: config)
        }()

        ImagePipeline.shared = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
        }
    }
}
