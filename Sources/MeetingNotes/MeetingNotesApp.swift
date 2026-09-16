import SwiftUI

@main
struct MeetingNotesApp: App {
    @State private var storage = AppStorageManager()
    @State private var recorder = RecordingCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(storage)
                .environment(recorder)
                .frame(minWidth: 720, minHeight: 460)
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
