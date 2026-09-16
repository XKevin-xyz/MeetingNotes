import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppStorageManager.self) private var storage
    @Environment(RecordingCoordinator.self) private var recorder
    @Environment(\.openSettings) private var openSettings
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var pulse = false
    @State private var speakerToRename: RenameTarget?
    @State private var sessionToRename: MeetingSession?
    @State private var sessionToDelete: MeetingSession?
    @State private var showOnboarding = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), Color(nsColor: .windowBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MeetingNotes")
                            .font(.title3.weight(.bold))
                        Text("Rustige, lokale vergadernotities")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if recorder.isRecording {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                                .scaleEffect(pulse ? 1.35 : 0.85)
                            Text("LIVE")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.red.opacity(0.12), in: Capsule())
                    }
                }

                VStack(spacing: 14) {
                    BreathingWaveform(isActive: recorder.isRecording)
                    Text(recorder.isRecording ? "Je vergadering wordt opgenomen" : "Klaar voor je vergadering")
                        .font(.title2.weight(.semibold))
                    Text(recorder.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(recorder.isRecording ? .red.opacity(0.35) : .white.opacity(0.08), lineWidth: 1)
                }

                if recorder.isTranscribing {
                    TranscriptionProgressView(startedAt: recorder.transcriptionStartedAt)
                }

                HStack(spacing: 10) {
                    Button(recorder.isRecording ? "Stop opname" : "Start opname") {
                        Task { await recorder.toggleRecording(storage: storage) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(recorder.isRecording ? .red : .accentColor)

                    if let latestSessionURL = recorder.latestSessionURL {
                        Button("Open laatste opname") {
                            NSWorkspace.shared.activateFileViewerSelecting([latestSessionURL])
                        }
                        Button("Transcribeer Nederlands") {
                            Task { await recorder.transcribeLatest(storage: storage) }
                        }
                        if let latestTranscriptURL = recorder.latestTranscriptURL {
                            Button("Open transcript") {
                                NSWorkspace.shared.open(latestTranscriptURL)
                            }
                        }
                    }
                    Button("Instellingen…") {
                        openSettings()
                    }
                }

                if !storage.sessions.isEmpty {
                    MeetingSessionsView(
                        sessions: storage.sessions,
                        onSelect: { session in
                            do {
                                try recorder.loadSession(session)
                            } catch {
                                recorder.setStatus("Vergadering kon niet worden geladen: \(error.localizedDescription)")
                            }
                        },
                        onRename: { session in sessionToRename = session },
                        onDelete: { session in sessionToDelete = session }
                    )
                }

                if let transcript = recorder.transcript {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Transcriptie", systemImage: "text.quote")
                                .font(.headline)
                            Spacer()
                            Text("\(transcript.segments.count) segmenten")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(transcript.segments) { segment in
                                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                                        Text("[\(formatTime(segment.start))]")
                                            .foregroundStyle(.secondary)
                                        Button(storage.displaySpeakerName(for: segment.speaker)) {
                                            speakerToRename = RenameTarget(
                                                label: segment.speaker,
                                                currentName: storage.displaySpeakerName(for: segment.speaker)
                                            )
                                        }
                                        .buttonStyle(.borderless)
                                        .fontWeight(.semibold)
                                        Text(": \(segment.text)")
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 180)
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(32)
        }
        .onChange(of: recorder.isRecording) { _, isRecording in
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = isRecording
            }
        }
        .sheet(item: $speakerToRename) { target in
            RenameSpeakerView(target: target) { newName in
                recorder.renameSpeaker(label: target.label, to: newName, storage: storage)
            }
        }
        .sheet(item: $sessionToRename) { session in
            RenameSessionView(session: session) { title in
                storage.renameSession(session, to: title)
            }
        }
        .confirmationDialog(
            "Deze vergadering verwijderen?",
            isPresented: Binding(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Verwijder vergadering", role: .destructive) {
                if let sessionToDelete {
                    storage.deleteSession(sessionToDelete)
                    if recorder.latestSessionURL == sessionToDelete.folderURL {
                        recorder.clearLoadedSession()
                    }
                }
                sessionToDelete = nil
            }
            Button("Annuleer", role: .cancel) { sessionToDelete = nil }
        } message: {
            Text("De audio en transcriptiebestanden van deze vergadering worden verwijderd.")
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                hasSeenOnboarding = true
                showOnboarding = false
            }
        }
        .onAppear {
            if !hasSeenOnboarding {
                showOnboarding = true
            }
        }
        .onChange(of: hasSeenOnboarding) { _, hasSeen in
            if !hasSeen {
                showOnboarding = true
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remaining = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, remaining)
    }
}

private struct MeetingSessionsView: View {
    let sessions: [MeetingSession]
    let onSelect: (MeetingSession) -> Void
    let onRename: (MeetingSession) -> Void
    let onDelete: (MeetingSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Vergaderingen", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            ForEach(sessions.prefix(5)) { session in
                HStack(spacing: 10) {
                    Button {
                        onSelect(session)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(session.hasTranscript ? "Transcriptie beschikbaar" : "Alleen audio beschikbaar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Menu {
                        Button("Hernoemen") { onRename(session) }
                        Button("Open in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([session.folderURL])
                        }
                        if session.hasTranscript {
                            Button("Open transcript") {
                                NSWorkspace.shared.open(session.transcriptURL)
                            }
                        }
                        Divider()
                        Button("Verwijderen", role: .destructive) { onDelete(session) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                    .menuStyle(.borderlessButton)
                }
                .padding(.vertical, 5)
                if session.id != sessions.prefix(5).last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct RenameSessionView: View {
    let session: MeetingSession
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String

    init(session: MeetingSession, onSave: @escaping (String) -> Void) {
        self.session = session
        self.onSave = onSave
        _title = State(initialValue: session.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vergadering hernoemen")
                .font(.headline)
            TextField("Naam", text: $title)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Annuleer") { dismiss() }
                Button("Opslaan") {
                    onSave(title)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

private struct RenameTarget: Identifiable {
    let id = UUID()
    let label: String
    let currentName: String
}

private struct RenameSpeakerView: View {
    let target: RenameTarget
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(target: RenameTarget, onSave: @escaping (String) -> Void) {
        self.target = target
        self.onSave = onSave
        _name = State(initialValue: target.currentName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Spreker hernoemen")
                .font(.headline)
            Text("Geef \(target.label) een herkenbare naam.")
                .foregroundStyle(.secondary)
            TextField("Naam", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Annuleer") { dismiss() }
                Button("Opslaan") {
                    onSave(name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

private struct BreathingWaveform: View {
    let isActive: Bool
    @State private var phase = false
    private let heights: [CGFloat] = [18, 32, 52, 28, 42, 64, 34, 54, 28, 44, 20]

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(isActive ? Color.red : Color.accentColor)
                    .frame(width: 7, height: isActive && phase ? height : max(12, height * 0.55))
            }
        }
        .frame(height: 68)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: phase)
        .onAppear { phase = isActive }
        .onChange(of: isActive) { _, active in phase = active }
    }
}

private struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let features: [(icon: String, color: Color, title: String, description: String)] = [
        ("waveform", .blue, "Neem elke vergadering op", "Werkt met Meet, Teams, Zoom, Discord en andere apps via je microfoon en systeemaudio."),
        ("text.quote", .purple, "Transcriptie in het Nederlands", "Laat je gesprek lokaal omzetten naar tekst, met tijdstempels en herkenbare sprekers."),
        ("lock.shield", .green, "Privé en overzichtelijk", "Je opnames, transcripties en modellen blijven op je Mac en zijn makkelijk terug te vinden of te verwijderen.")
    ]

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                Text("Welkom bij MeetingNotes")
                    .font(.title2.weight(.bold))
                Spacer()
            }

            let feature = features[page]
            VStack(spacing: 18) {
                Image(systemName: feature.icon)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(feature.color)
                    .frame(width: 92, height: 92)
                    .background(feature.color.opacity(0.13), in: Circle())
                Text(feature.title)
                    .font(.title3.weight(.semibold))
                Text(feature.description)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)
            }
            .id(page)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            .frame(height: 230)

            HStack(spacing: 7) {
                ForEach(features.indices, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: index == page ? 9 : 7, height: index == page ? 9 : 7)
                }
            }

            HStack {
                Button("Overslaan") {
                    onFinish()
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(page == features.count - 1 ? "Aan de slag" : "Volgende") {
                    if page == features.count - 1 {
                        onFinish()
                    } else {
                        withAnimation(.easeInOut) { page += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 560, height: 430)
    }
}

private struct TranscriptionProgressView: View {
    let startedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Transcriptie bezig", systemImage: "text.badge.checkmark")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(elapsedText(at: context.date))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView()
                Text("De eerste verwerking kan langer duren omdat het lokale model wordt geladen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func elapsedText(at date: Date) -> String {
        guard let startedAt else { return "00:00" }
        let seconds = max(0, Int(date.timeIntervalSince(startedAt)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct MenuBarStatusView: View {
    @Environment(RecordingCoordinator.self) private var recorder
    @Environment(AppStorageManager.self) private var storage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                recorder.isRecording ? "Opname actief" : "MeetingNotes",
                systemImage: recorder.isRecording ? "record.circle.fill" : "waveform"
            )
            .foregroundStyle(recorder.isRecording ? .red : .primary)

            Text(recorder.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 240, alignment: .leading)

            if recorder.isRecording {
                Button("Stop opname") {
                    Task { await recorder.toggleRecording(storage: storage) }
                }
            }

            Divider()

            Button("Open MeetingNotes") {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .padding(10)
    }
}
