import Foundation
import Models

// @DependencyClient
struct APIClient {
    var fetchUser: (UUID) async throws -> User
}
