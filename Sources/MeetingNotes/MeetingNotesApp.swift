import SwiftUI

@main
struct MeetingNotesApp: App {
    @State private var storage = AppStorageManager()
    @State private var recorder = RecordingCoordinator()

    var body: some Scene {
        WindowGroup {
            PremiumContentView()
                .environment(storage)
                .environment(recorder)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsDashboardView()
                .environment(storage)
        }

        MenuBarExtra {
            MenuBarStatusView()
                .environment(storage)
                .environment(recorder)
        } label: {
            Image(systemName: recorder.isRecording ? "record.circle.fill" : "waveform")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(recorder.isRecording ? .red : .primary)
        }
    }
}
