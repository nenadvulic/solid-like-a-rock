import Foundation

/// Protocol OWNED by the Domain. Infrastructure implements it (Dependency Inversion).
public protocol UserRepository {
    func user(id: UUID) async throws -> User
}
