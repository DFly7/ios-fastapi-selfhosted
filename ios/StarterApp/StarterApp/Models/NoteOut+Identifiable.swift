import Foundation

// `NoteOut` comes from GeneratedModels.swift (synced from Pydantic). SwiftUI’s
// `ForEach(items) { … }` requires `Identifiable`; we attach that here instead of
// editing generated code or repeating `id: \.id` at every call site.
extension NoteOut: Identifiable {}
