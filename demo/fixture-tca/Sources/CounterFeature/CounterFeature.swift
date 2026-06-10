import Foundation
import ComposableArchitecture
import Models

@Reducer
struct CounterFeature {
    struct State: Equatable { var count = 0 }
    enum Action { case increment }
}
