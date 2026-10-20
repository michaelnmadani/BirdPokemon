import SwiftUI

struct CapturedBadgeView: View {
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.caption)
            .foregroundStyle(.white)
            .padding(5)
            .background(Color.accentColor, in: Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }
}
