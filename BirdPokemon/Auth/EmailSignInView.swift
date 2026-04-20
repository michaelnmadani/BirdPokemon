import SwiftUI

struct EmailSignInView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Email", text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                }

                Section {
                    Button("Sign in") {
                        Task { await viewModel.signIn() }
                    }
                    .disabled(viewModel.email.isEmpty || viewModel.password.isEmpty)

                    Button("Forgot password?") {
                        Task { await viewModel.sendPasswordReset() }
                    }
                    .font(.footnote)
                }

                if let message = viewModel.errorMessage {
                    Section { Text(message).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if viewModel.isLoading { LoadingView(message: "Signing in…") }
            }
        }
    }
}
