import SwiftUI
import NukeUI

struct AsyncRemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable()
                     .aspectRatio(contentMode: contentMode == .fill ? .fill : .fit)
            } else if state.error != nil {
                Color(.secondarySystemBackground)
                    .overlay(Image(systemName: "bird").foregroundStyle(.tertiary))
            } else {
                Color(.secondarySystemBackground)
                    .overlay(ProgressView())
            }
        }
    }
}
