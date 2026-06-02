import Foundation

/// Core business entity. No knowledge of UI, DB or frameworks.
public struct User: Equatable {
    public let id: UUID
    public let name: String
    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}
