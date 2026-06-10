import Foundation
import ComposableArchitecture
import CounterFeature
import LoginFeature

// Root composer — the one place allowed to wire features together.
@Reducer
struct AppFeature {
    struct State: Equatable {
        var counter = CounterFeature.State()
        var login = LoginFeature.State()
    }
    enum Action { case counter(CounterFeature.Action), login(LoginFeature.Action) }
}
