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
                Section("Giờ học") {
                    DatePicker("Bắt đầu", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Kết thúc", selection: $end, displayedComponents: .hourAndMinute)
                    Stepper("Đổi từ mỗi \(interval) phút", value: $interval, in: 1...1440)
                    Text("Bao gồm giờ bắt đầu, không bao gồm giờ kết thúc. Nếu giờ bắt đầu muộn hơn giờ kết thúc, lịch chạy qua nửa đêm.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Thông báo") {
                    Toggle("Nhắc học bằng thông báo", isOn: $enabled)
                        .onChange(of: enabled) { _, value in
                            Task {
                                if value {
                                    do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
                                    catch { message = "Không xin được quyền thông báo. Hãy thử lại hoặc mở Cài đặt." }
                                    await refreshPermission()
                                }
                                // Persist the switch immediately so closing the sheet without "Lưu" keeps it.
                                var stored = WidgetProgressStore.schedule
                                stored.notificationsEnabled = value
                                WidgetProgressStore.updateSchedule(stored)
                                await VocabularyNotifications.reschedule()
                            }
                        }
                    Text(permissionText).font(.footnote).foregroundStyle(.secondary)
                    if status == .denied {
                        Button("Mở Cài đặt để cho phép thông báo") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                    }
                }
                if let message { Text(message).foregroundStyle(.red) }
            }
            .navigationTitle("Lịch học")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu") { save() } }
            }
            .task { await refreshPermission() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshPermission() } }
            }
        }
    }

    private var permissionText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "Đã cho phép. Âm báo đọc từ tiếng Anh; iOS có thể tắt âm theo cài đặt thiết bị."
        case .denied: return "Thông báo bị từ chối. Mở Cài đặt → Thông báo để cho phép."
        default: return "Bật thông báo để xin quyền hiển thị và phát âm báo."
        }
    }

    private func refreshPermission() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func save() {
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: end)
        let value = VocabularySchedule(startMinute: (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0),
                                       endMinute: (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0),
                                       intervalMinutes: interval, notificationsEnabled: enabled)
        guard WidgetProgressStore.updateSchedule(value) else {
            message = "Giờ bắt đầu và kết thúc phải khác nhau; khoảng đổi từ phải là số phút dương."
            return
        }
        WidgetCenter.shared.reloadAllTimelines()
        Task { await VocabularyNotifications.reschedule() }
        dismiss()
    }
}
