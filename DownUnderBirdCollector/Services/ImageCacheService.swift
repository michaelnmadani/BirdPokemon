import Foundation
import Nuke

enum ImageCacheService {
    /// Species thumbnails go into Nuke's aggressive disk cache, which ignores
    /// HTTP cache headers — once a photo has been seen it stays available
    /// offline (up to the size limit).
    static func configure() {
        var configuration = ImagePipeline.Configuration.withDataCache(
            name: "DownUnderBirdCollector.SpeciesImages",
            sizeLimit: 300 * 1024 * 1024
        )
        configuration.isProgressiveDecodingEnabled = true
        ImagePipeline.shared = ImagePipeline(configuration: configuration)
    }
}
