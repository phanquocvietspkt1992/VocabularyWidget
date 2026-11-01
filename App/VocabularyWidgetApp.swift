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
    @StateObject private var topicModel = TopicSelectionModel()
    @StateObject private var detailRouter = VocabularyDetailRouter()
    private let notificationDelegate: ForegroundNotificationDelegate

    init() {
        let delegate = ForegroundNotificationDelegate()
        notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
        WidgetProgressStore.ensureSelectedTopicInitialized()
    }

    var body: some Scene {
        WindowGroup {
            TopicPickerView(model: topicModel, detailRouter: detailRouter)
                .sheet(item: Binding(get: { detailRouter.state.detail }, set: { value in
                    if value == nil { detailRouter.close() }
                })) { session in
                    VocabularyWordDetailView(session: session, router: detailRouter).id(session.id)
                }
                .onOpenURL { url in detailRouter.open(url, blocked: topicModel.blocksWordDetail) }
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
