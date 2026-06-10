import Foundation

// Pure domain types, shared by every feature. No local dependencies.
public struct User: Equatable {
    public let id: UUID
    public var name: String
}
