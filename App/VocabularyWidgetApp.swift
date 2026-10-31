import SwiftUI
import WidgetKit

@main
struct VocabularyWidgetApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TopicPickerView()
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
        }
    }
}
