import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var authService
    @State private var showingAuth = false

    var body: some View {
        Group {
            if authService.isCheckingInitialSession {
                ProgressView("Loading…")
            } else if authService.isAuthenticated {
                ContentView()
            } else {
                signedOutPrompt
            }
        }
        .sheet(isPresented: $showingAuth) {
            AuthView()
                .environment(authService)
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthed in
            if isAuthed { showingAuth = false }
        }
    }

    private var signedOutPrompt: some View {
        VStack(spacing: 24) {
            Text("Starter")
                .font(.largeTitle.bold())
            Text("Sign in to continue")
                .foregroundStyle(.secondary)
            Button("Sign In") { showingAuth = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("auth.openSignIn")
        }
        .padding()
    }
}

#Preview("Signed out") {
    RootView()
        .environment(AuthService.previewSignedOut)
}

#Preview("Signed in") {
    RootView()
        .environment(AuthService.previewAuthenticated)
}
