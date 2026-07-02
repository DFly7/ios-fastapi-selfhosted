import AuthenticationServices
import CryptoKit
import SwiftUI

struct AuthView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var authMode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var currentNonce: String?

    enum AuthMode: String, CaseIterable {
        case signIn = "Sign In"
        case register = "Register"
        case magicLink = "Magic Link"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Mode", selection: $authMode) {
                        ForEach(AuthMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .padding(12)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("auth.email")

                    if authMode != .magicLink {
                        SecureField("Password", text: $password)
                            .textContentType(authMode == .register ? .newPassword : .password)
                            .padding(12)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityIdentifier("auth.password")
                    }

                    if let err = authService.errorMessage {
                        Label(err, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let info = authService.infoMessage {
                        Label(info, systemImage: "envelope.fill")
                            .foregroundStyle(.green)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: handlePrimaryAction) {
                        Group {
                            if authService.isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            } else {
                                Text(primaryButtonTitle)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("auth.submit")
                    .disabled(
                        email.isEmpty
                            || (authMode != .magicLink && password.isEmpty)
                            || authService.isLoading
                    )

                    Divider().padding(.vertical, 4)

                    Button(role: .none) {
                        Task { @MainActor in
                            await authService.signInWithGoogle()
                        }
                    } label: {
                        Text("Continue with Google")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)

                    SignInWithAppleButton(
                        onRequest: { request in
                            guard let nonce = randomNonceString() else { return }
                            currentNonce = nonce
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = sha256(nonce)
                        },
                        onCompletion: handleAppleCompletion
                    )
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding()
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var primaryButtonTitle: String {
        switch authMode {
        case .signIn: "Log In"
        case .register: "Create Account"
        case .magicLink: "Send Magic Link"
        }
    }

    private func handlePrimaryAction() {
        Task { @MainActor in
            switch authMode {
            case .signIn:
                await authService.signIn(email: email, password: password)
            case .register:
                await authService.register(email: email, password: password)
            case .magicLink:
                await authService.sendMagicLink(email: email)
            }
        }
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authResults):
            guard let credential = authResults.credential as? ASAuthorizationAppleIDCredential else { return }
            guard let nonce = currentNonce else { return }
            guard let idTokenData = credential.identityToken,
                  let idTokenString = String(data: idTokenData, encoding: .utf8) else { return }
            Task { @MainActor in
                await authService.signInWithApple(idToken: idTokenString, nonce: nonce)
            }
        case .failure(let error):
            Task { @MainActor in
                authService.errorMessage = AuthService.userFacingMessage(for: error)
            }
        }
    }

    private func randomNonceString(length: Int = 32) -> String? {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        guard status == errSecSuccess else { return nil }
        return Data(randomBytes).map { String(format: "%02x", $0) }.joined()
    }

    private func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    AuthView()
        .environment(AuthService.previewSignedOut)
}
