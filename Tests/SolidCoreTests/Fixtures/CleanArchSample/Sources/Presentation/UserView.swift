import SwiftUI       // OK: deny-mode layer, any UI framework is fine
import Application   // OK: the UI drives use cases

public struct UserView {
    private let fetchUser: FetchUserUseCase
    public init(fetchUser: FetchUserUseCase) {
        self.fetchUser = fetchUser
    }
}
