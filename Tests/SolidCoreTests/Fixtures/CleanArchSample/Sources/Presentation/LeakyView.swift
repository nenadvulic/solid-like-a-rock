import SwiftUI
import Infrastructure   // VIOLATION: UI reaching straight into the data layer

public struct LeakyView {
    let store = CoreDataUserStore()
}
