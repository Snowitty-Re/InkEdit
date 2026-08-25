import SwiftData
import SwiftUI

@main
struct InkEditApp: App {
    private let modelContainer: ModelContainer = {
        do {
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: LibraryBook.self, configurations: configuration)
            }
            return try ModelContainer(for: LibraryBook.self)
        } catch {
            fatalError("Could not create the InkEdit library: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
