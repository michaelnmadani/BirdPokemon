import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @StateObject private var viewModel = AuthViewModel()
    @State private var showEmailFlow = false
    @State private var isSignUp = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "bird.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .foregroundStyle(Color.accentColor)

                    Text("BirdPokemon")
                        .font(.largeTitle.bold())

                    Text("Catch every bird.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(spacing: 14) {
                    SignInWithAppleButton(.signIn) { request in
                        viewModel.prepareAppleRequest(request)
                    } onCompletion: { result in
                        Task { await viewModel.handleAppleCompletion(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(12)

                    Button {
                        isSignUp = false
                        showEmailFlow = true
                    } label: {
                        Label("Continue with email", systemImage: "envelope.fill")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Create account") {
                        isSignUp = true
                        showEmailFlow = true
                    }
                    .font(.footnote)
                }
                .padding(.horizontal, 24)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()
            }
            .overlay {
                if viewModel.isLoading { LoadingView(message: "Signing in…") }
            }
            .sheet(isPresented: $showEmailFlow) {
                if isSignUp {
                    EmailSignUpView(viewModel: viewModel)
                } else {
                    EmailSignInView(viewModel: viewModel)
                }
            }
        }
    }
}

#Preview {
    AuthView()
}
