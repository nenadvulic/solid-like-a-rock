import Foundation
import Domain   // OK: implements a Domain-owned protocol (inward dependency)

public final class CoreDataUserStore: UserRepository {
    public init() {}
    public func user(id: UUID) async throws -> User {
        User(id: id, name: "Ada Lovelace")
    }
}
