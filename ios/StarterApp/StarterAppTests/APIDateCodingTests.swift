import Foundation
import Testing
@testable import StarterApp

@MainActor
@Suite("API date coding")
struct APIDateCodingTests {
  private let decoder = APIDateCoding.makeDecoder()

  @Test("Decodes FastAPI timestamps with fractional seconds")
  func fractionalSeconds() throws {
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "user_id": "00000000-0000-0000-0000-000000000002",
      "title": "Hello",
      "body": null,
      "created_at": "2026-07-07T16:11:40.406755Z",
      "updated_at": "2026-07-07T16:11:40.406755Z"
    }
    """
    let note = try decoder.decode(NoteOut.self, from: Data(json.utf8))
    #expect(note.title == "Hello")
  }

  @Test("Still decodes whole-second timestamps")
  func wholeSeconds() throws {
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "user_id": "00000000-0000-0000-0000-000000000002",
      "title": "Hello",
      "body": null,
      "created_at": "2026-01-01T00:00:00Z",
      "updated_at": "2026-01-01T00:00:00Z"
    }
    """
    let note = try decoder.decode(NoteOut.self, from: Data(json.utf8))
    #expect(note.title == "Hello")
  }
}
