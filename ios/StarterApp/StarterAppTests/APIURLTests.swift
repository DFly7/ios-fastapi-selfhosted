import Foundation
import Testing
@testable import StarterApp

@Suite("API URL building")
struct APIURLTests {
  @Test("Preserves query strings instead of encoding them into the path")
  func queryStringPreserved() {
    let url = BackendAPIService.requestURL(path: "api/v1/me/notes?limit=20&offset=0")
    #expect(url.path.hasSuffix("/api/v1/me/notes"))
    #expect(url.query == "limit=20&offset=0")
  }

  @Test("Resource detail query stays out of the UUID path")
  func resourceDetailQuery() {
    let id = "00000000-0000-0000-0000-000000000001"
    let url = BackendAPIService.requestURL(path: "api/v1/me/notes/\(id)?unit=kg")
    #expect(url.path.hasSuffix("/api/v1/me/notes/\(id)"))
    #expect(url.query == "unit=kg")
  }
}
