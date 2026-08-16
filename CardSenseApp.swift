import SwiftUI

@main
struct CardSenseApp: App {
    @StateObject private var collection = CollectionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(collection)
        }
    }
}
