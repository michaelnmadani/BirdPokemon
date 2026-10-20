import UIKit
@testable import DownUnderBirdCollector

enum TestFixtures {
    static func species(code: String = "testspc",
                        family: String = "Testidae",
                        familyCommonName: String? = nil,
                        size: SizeCategory = .medium,
                        colors: [BirdColor] = [.brown],
                        regions: [String] = ["AU"],
                        name: String = "Test Bird") -> Species {
        Species(
            ebirdCode: code,
            commonName: name,
            scientificName: "Testus testus",
            order: "Testiformes",
            family: family,
            familyCommonName: familyCommonName,
            category: "species",
            sizeCategory: size,
            primaryColors: colors,
            regionCodes: regions,
            thumbnailURL: nil,
            thumbnailAttribution: nil,
            thumbnailLicense: nil,
            wikipediaURL: nil,
            ebirdURL: "https://example.com"
        )
    }

    /// A solid-colour image of the given pixel size.
    static func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
