import Foundation
import ComposableArchitecture
import Models
import CounterFeature  // ❌ a feature reaching into a sibling feature

@Reducer
struct LoginFeature {
    struct State: Equatable { var user: User? }
    enum Action { case login }
}
