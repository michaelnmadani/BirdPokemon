import SwiftUI

struct EmailSignUpView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Your account") {
                    TextField("Display name (optional)", text: $viewModel.displayName)
                        .textContentType(.name)
                    TextField("Email", text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("Password (8+ characters)", text: $viewModel.password)
                        .textContentType(.newPassword)
                }

                Section {
                    Button("Create account") {
                        Task { await viewModel.signUp() }
                    }
                    .disabled(viewModel.email.isEmpty || viewModel.password.count < 8)
                }

                if let message = viewModel.errorMessage {
                    Section { Text(message).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Create account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if viewModel.isLoading { LoadingView(message: "Creating account…") }
            }
        }
    }
}
