import SwiftUI
import AVFoundation

/// "Hear its call": streams a species' reference recording. Needs a connection.
struct CallPlayerView: View {
    let species: Species

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var status: String?
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        if let url = species.call {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    toggle(url)
                } label: {
                    Label(isPlaying ? "Pause" : "Hear its call", systemImage: isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(isPlaying ? "Pause call" : "Hear the call of the \(species.commonName)")

                if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                if let credit = species.callCredit {
                    if let page = species.callPageURL.flatMap(URL.init(string:)) {
                        Link("Recording: \(credit)", destination: page)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Recording: \(credit)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .onDisappear(perform: stop)
        }
    }

    private func toggle(_ url: URL) {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        // Play even when the ring/silent switch is on, like any audio app.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        if player == nil {
            let item = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: item)
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    isPlaying = false
                    player?.seek(to: .zero)
                }
            }
        }
        status = nil
        player?.play()
        isPlaying = true
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if isPlaying, player?.currentItem?.status == .failed {
                status = "Couldn't play this recording. Playing calls needs an internet connection."
                isPlaying = false
            }
        }
    }

    private func stop() {
        player?.pause()
        isPlaying = false
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}
