import SwiftUI
import Domain

struct HomeView: View {
    var user: User?
    var body: some View { Text(user?.name ?? "Home") }
}
