import Foundation
import Infrastructure   // VIOLATION: Application must not depend on a concrete outer layer

/// Smell: reaches for a concrete store instead of the UserRepository protocol.
public struct BadUseCase {
    let store = CoreDataUserStore()
}
