import Foundation
import Models
import APIClient

// @Reducer
struct CounterFeature {
    struct State: Equatable { var count = 0 }
    enum Action { case increment, decrement }
}
