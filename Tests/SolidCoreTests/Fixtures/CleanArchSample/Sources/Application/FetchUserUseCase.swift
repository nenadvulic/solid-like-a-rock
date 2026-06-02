import Foundation
import Domain   // OK: Application orchestrates the Domain

public struct FetchUserUseCase {
    private let repository: UserRepository
    public init(repository: UserRepository) {
        self.repository = repository
    }
    public func callAsFunction(id: UUID) async throws -> User {
        try await repository.user(id: id)
    }
}
