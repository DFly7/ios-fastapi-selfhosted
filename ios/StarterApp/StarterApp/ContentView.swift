//
//  ContentView.swift
//  StarterApp
//

import SwiftUI

struct ContentView: View {
    @Environment(AuthService.self) private var authService
    @Environment(PurchaseService.self) private var purchases

    /// View model owns all async state. Declared with @State so SwiftUI tracks
    /// @Observable property changes and re-renders only what actually changed.
    @State private var viewModel = ContentViewModel()

    // Local UI-only state — purely presentational, not part of the model.
    @State private var isEditingDisplayName = false
    @State private var editingDisplayName = ""
    @State private var isShowingNoteComposer = false
    @State private var newNoteTitle = ""
    @State private var editingNoteId: UUID?
    @State private var editingNoteTitle = ""
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                secureTestSection
                profileSection
                proSection
                notesSection
            }
            .navigationTitle("Starter")
            .task { await viewModel.fetchNotes(auth: authService) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if let email = authService.userEmail {
                            Text(email)
                        }
                        Button("Sign Out", role: .destructive) {
                            authService.signOut()
                        }
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    proToolbarItem
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    // MARK: - Pro toolbar item

    /// Free: an "Upgrade" button that opens the paywall.
    /// Pro: a Menu with subscription management actions — a clean place to add
    /// "Manage Subscription" and "Restore Purchases" without cluttering the UI.
    @ViewBuilder
    private var proToolbarItem: some View {
        if purchases.isPro {
            Menu {
                Label("Pro Member", systemImage: "checkmark.seal.fill")
                Divider()
                Button("Manage Subscription") {
                    if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Restore Purchases") {
                    Task { try? await purchases.restorePurchases() }
                }
            } label: {
                Label("Pro", systemImage: "crown.fill")
                    .foregroundStyle(.yellow)
            }
        } else {
            Button { showPaywall = true } label: {
                Label("Upgrade", systemImage: "crown")
            }
        }
    }

    // MARK: - Pro section

    /// Demonstrates the canonical feature-gating pattern for this template.
    ///
    /// Copy this section when you want to gate your own feature behind a Pro subscription.
    /// The lock→crown SF Symbol morph fires automatically when `isPro` flips because
    /// the icon is a single `Image` view with `.contentTransition(.symbolEffect(.replace))`,
    /// giving SwiftUI a stable identity to animate against.
    private var proSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pro Analytics")
                        .font(.body)
                    Text(
                        purchases.isPro
                            ? "Active – all features unlocked"
                            : "Upgrade to Pro to unlock →"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .animation(.default, value: purchases.isPro)
                }
            } icon: {
                Image(systemName: purchases.isPro ? "crown.fill" : "lock.fill")
                    .foregroundStyle(purchases.isPro ? .yellow : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.default, value: purchases.isPro)
            }
            .onTapGesture {
                if !purchases.isPro { showPaywall = true }
            }
        } header: {
            Text("Pro Features")
        } footer: {
            if !purchases.isPro {
                Text("Tap the row or the crown icon in the toolbar to upgrade.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Secure test section

    private var secureTestSection: some View {
        Section("Backend (JWT)") {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Proves the app, Supabase session, and FastAPI `verify_jwt` share the same token. "
                        + "Backend: \(APIConfig.backendURL.host ?? APIConfig.backendURL.absoluteString)"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button {
                    Task { await viewModel.callSecureTest(auth: authService) }
                } label: {
                    if viewModel.isCallingSecureTest {
                        HStack { ProgressView(); Text("Calling /api/v1/secure-test…") }
                    } else {
                        Text("Call /api/v1/secure-test")
                    }
                }
                .disabled(viewModel.isCallingSecureTest)

                if let result = viewModel.secureTestResult {
                    Text(result.message).font(.subheadline)
                    if let uid = result.userId {
                        Text("user_id: \(uid)")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if let error = viewModel.secureTestError {
                    ErrorBanner(message: error.localizedDescription) {
                        Task { await viewModel.callSecureTest(auth: authService) }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Profile section (GET + PATCH demo)

    private var profileSection: some View {
        Section("My Profile") {
            VStack(alignment: .leading, spacing: 8) {
                Text("FastAPI loads your `profiles` row with your JWT; Postgres RLS only allows your own id.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let profile = viewModel.profile {
                    profileSummary(profile)

                    if isEditingDisplayName {
                        // PATCH /me/profile demo — inline edit form
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                TextField("Display name", text: $editingDisplayName)
                                    .textFieldStyle(.roundedBorder)
                                Button("Save") {
                                    let name = editingDisplayName
                                    isEditingDisplayName = false
                                    Task {
                                        await viewModel.updateProfile(
                                            displayName: name,
                                            auth: authService
                                        )
                                    }
                                }
                                .disabled(viewModel.isUpdatingProfile || editingDisplayName.isEmpty)
                                Button("Cancel") { isEditingDisplayName = false }
                                    .foregroundStyle(.secondary)
                            }
                            if viewModel.isUpdatingProfile {
                                HStack { ProgressView().scaleEffect(0.75); Text("Saving…").font(.caption) }
                            }
                            if let err = viewModel.updateProfileError {
                                ErrorBanner(message: err.localizedDescription, onRetry: nil)
                            }
                        }
                        .padding(.top, 4)
                    } else {
                        Button("Edit display name") {
                            editingDisplayName = profile.displayName ?? ""
                            isEditingDisplayName = true
                        }
                        .font(.footnote)
                    }
                } else {
                    // GET /me/profile demo — button-triggered fetch
                    Button {
                        Task { await viewModel.fetchProfile(auth: authService) }
                    } label: {
                        if viewModel.isLoadingProfile {
                            HStack { ProgressView(); Text("GET /api/v1/me/profile…") }
                        } else {
                            Text("Fetch my profile")
                        }
                    }
                    .disabled(viewModel.isLoadingProfile)
                }

                if let error = viewModel.profileError {
                    ErrorBanner(message: error.localizedDescription) {
                        Task { await viewModel.fetchProfile(auth: authService) }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Notes section (full CRUD demo)

    private var notesSection: some View {
        Section {
            Text(
                "Full CRUD: POST (create, 201), GET (list), PATCH (update), DELETE (204) — "
                + "all through the repo → service → router chain."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            if viewModel.isLoadingNotes {
                HStack { ProgressView(); Text("Loading notes…").font(.footnote) }
            }

            ForEach(viewModel.notes) { note in
                if editingNoteId == note.id {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Note title", text: $editingNoteTitle)
                                .textFieldStyle(.roundedBorder)
                            Button("Save") {
                                let id = note.id
                                let title = editingNoteTitle
                                editingNoteId = nil
                                Task {
                                    await viewModel.updateNote(
                                        id: id,
                                        title: title,
                                        auth: authService
                                    )
                                }
                            }
                            .disabled(
                                editingNoteTitle.trimmingCharacters(in: .whitespaces).isEmpty
                                    || viewModel.isUpdatingNote
                            )
                            Button("Cancel") { editingNoteId = nil }
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title).font(.subheadline)
                        Text(note.createdAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            editingNoteTitle = note.title
                            editingNoteId = note.id
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteNote(id: note.id, auth: authService) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            if isShowingNoteComposer {
                HStack {
                    TextField("Note title", text: $newNoteTitle)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let title = newNoteTitle
                        newNoteTitle = ""
                        isShowingNoteComposer = false
                        Task { await viewModel.createNote(title: title, auth: authService) }
                    }
                    .disabled(newNoteTitle.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isCreatingNote)
                    Button("Cancel") { newNoteTitle = ""; isShowingNoteComposer = false }
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    isShowingNoteComposer = true
                } label: {
                    if viewModel.isCreatingNote {
                        HStack { ProgressView().scaleEffect(0.75); Text("Creating…") }
                    } else {
                        Label("New Note", systemImage: "plus.circle")
                    }
                }
                .disabled(viewModel.isCreatingNote)
            }

            if let error = viewModel.notesError {
                ErrorBanner(message: error.localizedDescription) {
                    Task { await viewModel.fetchNotes(auth: authService) }
                }
            }

            if let error = viewModel.updateNoteError {
                ErrorBanner(message: error.localizedDescription, onRetry: nil)
            }
        } header: {
            Text("Notes")
        } footer: {
            if !viewModel.notes.isEmpty {
                Text("Swipe right to edit · swipe left to delete.")
            }
        }
    }

    // MARK: - Profile avatar helpers

    @ViewBuilder
    private func profileSummary(_ profile: ProfileOut) -> some View {
        HStack(alignment: .top, spacing: 12) {
            profileAvatar(urlString: profile.avatarUrl)
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if let name = profile.displayName, !name.isEmpty {
                        Text(name)
                    } else {
                        Text("No display name").foregroundStyle(.secondary)
                    }
                }
                .font(.headline)
                Text(profile.id.uuidString)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text(profile.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func profileAvatar(urlString: String?) -> some View {
        let size: CGFloat = 56
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView().frame(width: size, height: size)
                case .success(let image):
                    image.resizable().scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                case .failure:
                    avatarPlaceholder(size: size)
                @unknown default:
                    avatarPlaceholder(size: size)
                }
            }
        } else {
            avatarPlaceholder(size: size)
        }
    }

    private func avatarPlaceholder(size: CGFloat) -> some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: size * 0.85))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}

// MARK: - Reusable error banner

/// Displays an error message with an optional Retry button.
/// Drop this anywhere a network call can fail.
private struct ErrorBanner: View {
    let message: String
    let onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onRetry {
                Button("Retry", action: onRetry)
                    .font(.footnote.bold())
            }
        }
        .padding(8)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview("Free user") {
    ContentView()
        .environment(AuthService.previewAuthenticated)
        .environment(PurchaseService.previewFree)
}

#Preview("Pro user") {
    ContentView()
        .environment(AuthService.previewAuthenticated)
        .environment(PurchaseService.previewSubscribed)
}
