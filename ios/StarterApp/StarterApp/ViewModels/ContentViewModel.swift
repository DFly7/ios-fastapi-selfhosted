import Foundation
import Observation

/// View model for `ContentView`.
///
/// Separating state and async calls from the view keeps SwiftUI previews fast,
/// makes unit testing straightforward, and keeps the view a pure rendering layer.
///
/// ### Error handling
/// Each operation exposes a typed `AppError?` rather than a raw `String?`.
/// This lets callers branch on the *kind* of failure (e.g. show a sign-in prompt
/// on `.notSignedIn`, a retry button on `.networkFailure`) without parsing strings.
/// The view calls `error.localizedDescription` when it only needs a display string.
///
/// Usage in the view:
/// ```swift
/// @State private var viewModel = ContentViewModel()
/// ```
@Observable
final class ContentViewModel {

    // MARK: - Secure test

    var secureTestResult: BackendAPIService.SecureTestResponse?
    var secureTestError: AppError?
    var isCallingSecureTest = false

    // MARK: - Profile

    var profile: ProfileOut?
    var profileError: AppError?
    var isLoadingProfile = false

    // MARK: - Update profile

    var isUpdatingProfile = false
    var updateProfileError: AppError?

    // MARK: - Notes

    var notes: [NoteOut] = []
    var notesError: AppError?
    var isLoadingNotes = false
    var isCreatingNote = false

    // MARK: - Update note

    var isUpdatingNote = false
    var updateNoteError: AppError?

    // MARK: - Actions

    func callSecureTest(accessToken: String?) async {
        secureTestError = nil
        secureTestResult = nil
        isCallingSecureTest = true
        defer { isCallingSecureTest = false }
        do {
            secureTestResult = try await BackendAPIService.fetchSecureTest(accessToken: accessToken)
        } catch let appError as AppError {
            secureTestError = appError
        } catch {
            secureTestError = .networkFailure(underlying: error)
        }
    }

    func fetchProfile(accessToken: String?) async {
        profileError = nil
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        do {
            profile = try await BackendAPIService.fetchMyProfile(accessToken: accessToken)
        } catch let appError as AppError {
            profileError = appError
        } catch {
            profileError = .networkFailure(underlying: error)
        }
    }

    func updateProfile(displayName: String, accessToken: String?) async {
        updateProfileError = nil
        isUpdatingProfile = true
        defer { isUpdatingProfile = false }
        do {
            profile = try await BackendAPIService.updateMyProfile(
                displayName: displayName,
                accessToken: accessToken
            )
        } catch let appError as AppError {
            updateProfileError = appError
        } catch {
            updateProfileError = .networkFailure(underlying: error)
        }
    }

    func fetchNotes(accessToken: String?) async {
        notesError = nil
        isLoadingNotes = true
        defer { isLoadingNotes = false }
        do {
            notes = try await BackendAPIService.fetchNotes(accessToken: accessToken)
        } catch let appError as AppError {
            notesError = appError
        } catch {
            notesError = .networkFailure(underlying: error)
        }
    }

    func createNote(title: String, body: String? = nil, accessToken: String?) async {
        notesError = nil
        isCreatingNote = true
        defer { isCreatingNote = false }
        do {
            let note = try await BackendAPIService.createNote(title: title, body: body, accessToken: accessToken)
            notes.insert(note, at: 0)
        } catch let appError as AppError {
            notesError = appError
        } catch {
            notesError = .networkFailure(underlying: error)
        }
    }

    func updateNote(id: UUID, title: String, accessToken: String?) async {
        updateNoteError = nil
        isUpdatingNote = true
        defer { isUpdatingNote = false }
        do {
            let updated = try await BackendAPIService.updateNote(id: id, title: title, accessToken: accessToken)
            if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index] = updated
            }
        } catch let appError as AppError {
            updateNoteError = appError
        } catch {
            updateNoteError = .networkFailure(underlying: error)
        }
    }

    func deleteNote(id: UUID, accessToken: String?) async {
        do {
            try await BackendAPIService.deleteNote(id: id, accessToken: accessToken)
            notes.removeAll { $0.id == id }
        } catch let appError as AppError {
            notesError = appError
        } catch {
            notesError = .networkFailure(underlying: error)
        }
    }
}
