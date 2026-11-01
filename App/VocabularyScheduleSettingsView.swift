import SwiftUI
import WidgetKit
import UserNotifications

struct VocabularyScheduleSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var start: Date
    @State private var end: Date
    @State private var interval: Int
    @State private var enabled: Bool
    @State private var status = UNAuthorizationStatus.notDetermined
    @State private var message: String?

    init() {
        let schedule = WidgetProgressStore.schedule
        let calendar = Calendar.current
        _start = State(initialValue: calendar.date(bySettingHour: schedule.startMinute / 60, minute: schedule.startMinute % 60, second: 0, of: .now) ?? .now)
        _end = State(initialValue: calendar.date(bySettingHour: schedule.endMinute / 60, minute: schedule.endMinute % 60, second: 0, of: .now) ?? .now)
        _interval = State(initialValue: schedule.intervalMinutes)
        _enabled = State(initialValue: schedule.notificationsEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Study Hours") {
                    DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                    Stepper("Change word every \(interval) minutes", value: $interval, in: 1...1440)
                    Text("The start time is inclusive and the end time is exclusive. If the start is later than the end, the schedule runs overnight.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Notifications") {
                    Toggle("Study Reminders", isOn: Binding(get: { enabled }, set: { value in
                        enabled = value
                        Task { await updateReminders(value) }
                    }))
                    Text(permissionText).font(.footnote).foregroundStyle(.secondary)
                    if status == .denied {
                        Button("Open Settings to Allow Notifications") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                    }
                }
                if let message { Text(message).foregroundStyle(.red) }
            }
            .navigationTitle("Study Schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .task { await refreshPermission() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshPermission() } }
            }
        }
    }

    private var permissionText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "Allowed. Notification audio pronounces English words; iOS may silence it based on device settings."
        case .denied: return "Notifications are disabled. Open Settings → Notifications to allow them."
        default: return "Enable reminders to request permission for notifications and audio."
        }
    }

    private func refreshPermission() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func updateReminders(_ value: Bool) async {
        if value {
            do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
            catch { message = "Could not request notification permission. Try again or open Settings." }
            await refreshPermission()
        }
        var stored = WidgetProgressStore.schedule
        stored.notificationsEnabled = value
        guard WidgetProgressStore.updateSchedule(stored) else {
            enabled = WidgetProgressStore.schedule.notificationsEnabled
            message = "Could not save study reminders because the saved schedule could not be read. Existing saved data has not been changed."
            return
        }
        await VocabularyNotifications.reschedule()
    }

    private func save() {
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: end)
        let value = VocabularySchedule(startMinute: (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0),
                                       endMinute: (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0),
                                       intervalMinutes: interval, notificationsEnabled: enabled)
        guard value.isValid else {
            message = "Start and end times must differ, and the word interval must be a positive number of minutes."
            return
        }
        guard WidgetProgressStore.updateSchedule(value) else {
            message = "Could not save the study schedule. The saved schedule may be unreadable; existing saved data has not been changed."
            return
        }
        WidgetCenter.shared.reloadAllTimelines()
        Task { await VocabularyNotifications.reschedule() }
        dismiss()
    }
}
