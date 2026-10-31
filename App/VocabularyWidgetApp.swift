import SwiftUI
import WidgetKit
import UserNotifications

private final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

@main
struct VocabularyWidgetApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let notificationDelegate: ForegroundNotificationDelegate

    init() {
        let delegate = ForegroundNotificationDelegate()
        notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
        WidgetProgressStore.ensureSelectedTopicInitialized()
    }

    var body: some Scene {
        WindowGroup {
            TopicPickerView()
                .task { await VocabularyNotifications.reschedule() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        PronunciationAudioWarmup.prepareInForeground()
                        WidgetCenter.shared.reloadAllTimelines()
                        Task { await VocabularyNotifications.reschedule() }
                    }
                }
        }
    }
}
