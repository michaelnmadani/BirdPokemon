import SwiftUI
import NukeUI

/// Shows a remote image (cached by Nuke), a local file, or a placeholder
/// when there's no image at all.
struct AsyncRemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        if let url, url.isFileURL {
            LocalFileImage(url: url, contentMode: contentMode)
        } else if let url {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable()
                         .aspectRatio(contentMode: contentMode)
                } else if state.error != nil {
                    Placeholder()
                } else {
                    Color(.secondarySystemBackground)
                        .overlay(ProgressView())
                }
            }
        } else {
            Placeholder()
        }
    }
}

private struct Placeholder: View {
    var body: some View {
        Color(.secondarySystemBackground)
            .overlay(Image(systemName: "bird").font(.title2).foregroundStyle(.tertiary))
    }
}

private struct LocalFileImage: View {
    let url: URL
    let contentMode: ContentMode
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color(.secondarySystemBackground)
            }
        }
        .task(id: url) {
            let path = url.path
            image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: path)?.preparingForDisplay()
            }.value
        }
    }
}
