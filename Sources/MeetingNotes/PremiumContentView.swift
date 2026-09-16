import AppKit
import SwiftUI

struct PremiumContentView: View {
    private enum Route: Hashable {
        case overview
        case meetings
        case transcripts
        case audio
    }

    @Environment(AppStorageManager.self) private var storage
    @Environment(RecordingCoordinator.self) private var recorder
    @Environment(\.openSettings) private var openSettings
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var route: Route = .overview
    @State private var showOnboarding = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Group {
                switch route {
                case .overview:
                    OverviewScreen()
                case .meetings:
                    MeetingsLibraryScreen(filter: .all)
                case .transcripts:
                    MeetingsLibraryScreen(filter: .transcripts)
                case .audio:
                    MeetingsLibraryScreen(filter: .audio)
                }
            }
            .environment(storage)
            .environment(recorder)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await recorder.toggleRecording(storage: storage) }
                    } label: {
                        Label(
                            recorder.isRecording ? "Stop opname" : "Start opname",
                            systemImage: recorder.isRecording ? "stop.fill" : "record.circle"
                        )
                    }
                    .tint(recorder.isRecording ? .red : .accentColor)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .top) {
            if recorder.isRecording {
                RecordingHUD()
                    .environment(recorder)
                    .environment(storage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: recorder.isRecording)
        .sheet(isPresented: $showOnboarding) {
            PremiumOnboardingView {
                hasSeenOnboarding = true
                showOnboarding = false
            }
        }
        .onAppear {
            storage.refreshSessions()
            if !hasSeenOnboarding { showOnboarding = true }
        }
        .onChange(of: hasSeenOnboarding) { _, seen in
            if !seen { showOnboarding = true }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 31, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
                    .shadow(color: .blue.opacity(0.35), radius: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MeetingNotes")
                        .font(.headline.weight(.bold))
                    Text("Lokale vergaderingen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 18)

            List(selection: $route) {
                Section("Werkruimte") {
                    Label("Overzicht", systemImage: "rectangle.3.group.fill")
                        .tag(Route.overview)
                    Label("Vergaderingen", systemImage: "clock.arrow.circlepath")
                        .tag(Route.meetings)
                }

                Section("Bibliotheek") {
                    Label("Alle transcripties", systemImage: "text.quote")
                        .tag(Route.transcripts)
                    Label("Audio-opnames", systemImage: "waveform")
                        .tag(Route.audio)
                }
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Button {
                    openSettings()
                } label: {
                    Label("Instellingen", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    storage.revealRootInFinder()
                } label: {
                    Label("Open bestanden", systemImage: "folder")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                HStack(spacing: 7) {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                    Text("Lokale verwerking actief")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .background(.thinMaterial)
        .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 280)
    }
}

private struct OverviewScreen: View {
    @Environment(AppStorageManager.self) private var storage
    @Environment(RecordingCoordinator.self) private var recorder

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Goed dat je er bent")
                            .font(.largeTitle.weight(.bold))
                        Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !storage.sessions.isEmpty {
                        Text("\(storage.sessions.count) vergaderingen")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                RecordingHeroCard()
                    .environment(storage)
                    .environment(recorder)

                HStack(spacing: 14) {
                    MetricCard(title: "Vergaderingen", value: "\(storage.sessions.count)", icon: "calendar", tint: .blue)
                    MetricCard(
                        title: "Transcripties",
                        value: "\(storage.sessions.filter(\.hasTranscript).count)",
                        icon: "text.quote",
                        tint: .purple
                    )
                    MetricCard(title: "Lokale opslag", value: storage.formattedDataSize, icon: "internaldrive", tint: .green)
                }

                HStack {
                    Text("Recente vergaderingen")
                        .font(.title2.weight(.bold))
                    Spacer()
                    if !storage.sessions.isEmpty {
                        Text("Nieuwste eerst")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if storage.sessions.isEmpty {
                    EmptyMeetingsCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(storage.sessions.prefix(4)) { session in
                            CompactMeetingRow(session: session)
                            if session.id != storage.sessions.prefix(4).last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .padding(32)
            .frame(maxWidth: 1050, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Overzicht")
    }
}

private struct RecordingHeroCard: View {
    @Environment(AppStorageManager.self) private var storage
    @Environment(RecordingCoordinator.self) private var recorder
    @State private var animate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(recorder.isRecording ? "OPNAME ACTIEF" : "KLAAR VOOR JE MEETING", systemImage: recorder.isRecording ? "record.circle.fill" : "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(recorder.isRecording ? .red : .blue)
                    Text(recorder.isRecording ? "Blijf in je gesprek" : "Maak ruimte voor goede notulen")
                        .font(.title.weight(.bold))
                    Text(recorder.isRecording ? "Microfoon en systeemaudio worden lokaal vastgelegd." : "Neem op vanuit Meet, Teams, Zoom of Discord.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: recorder.isRecording ? "waveform.and.mic" : "waveform")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(recorder.isRecording ? .red : .blue)
                    .symbolEffect(.pulse, isActive: recorder.isRecording)
            }

            AnimatedWaveform(isActive: recorder.isRecording || animate)
                .frame(height: 76)
                .padding(.top, 18)

            HStack {
                Text(recorder.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    Task { await recorder.toggleRecording(storage: storage) }
                } label: {
                    Label(recorder.isRecording ? "Stop opname" : "Start opname", systemImage: recorder.isRecording ? "stop.fill" : "record.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? .red : .blue)
            }

            if let sessionURL = recorder.latestSessionURL, !recorder.isRecording {
                Divider()
                    .padding(.top, 16)
                HStack(spacing: 9) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([sessionURL])
                    } label: {
                        Label("Open opname", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await recorder.transcribeLatest(storage: storage) }
                    } label: {
                        Label(
                            recorder.isTranscribing ? "Transcriptie bezig…" : "Transcribeer Nederlands",
                            systemImage: recorder.isTranscribing ? "hourglass" : "text.quote"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(recorder.isTranscribing)

                    if let transcriptURL = recorder.latestTranscriptURL {
                        Button("Open transcript") {
                            NSWorkspace.shared.open(transcriptURL)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(26)
        .background {
            RoundedRectangle(cornerRadius: 26)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 26)
                        .fill(
                            LinearGradient(
                                colors: [
                                    (recorder.isRecording ? Color.red : Color.blue).opacity(0.15),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder((recorder.isRecording ? Color.red : Color.blue).opacity(0.22), lineWidth: 1)
        }
        .onAppear { animate = true }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17))
    }
}

private struct EmptyMeetingsCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 30))
                .foregroundStyle(.blue)
            Text("Je eerste vergadering staat hier")
                .font(.headline)
            Text("Start een opname om audio, transcriptie en notulen automatisch bij elkaar te bewaren.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(34)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct MeetingsLibraryScreen: View {
    enum Filter {
        case all
        case transcripts
        case audio
    }

    let filter: Filter
    @Environment(AppStorageManager.self) private var storage
    @Environment(RecordingCoordinator.self) private var recorder
    @State private var searchText = ""
    @State private var sessionToRename: MeetingSession?
    @State private var sessionToDelete: MeetingSession?

    private var filteredSessions: [MeetingSession] {
        let scoped: [MeetingSession]
        switch filter {
        case .all:
            scoped = storage.sessions
        case .transcripts:
            scoped = storage.sessions.filter(\.hasTranscript)
        case .audio:
            scoped = storage.sessions
        }
        guard !searchText.isEmpty else { return scoped }
        return scoped.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.largeTitle.weight(.bold))
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(filteredSessions.count) resultaten")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if filteredSessions.isEmpty {
                    EmptyMeetingsCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(filteredSessions) { session in
                            LibraryMeetingRow(
                                session: session,
                                onOpen: { load(session) },
                                onRename: { sessionToRename = session },
                                onDelete: { sessionToDelete = session }
                            )
                            if session.id != filteredSessions.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .padding(32)
            .frame(maxWidth: 1050, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Vergaderingen")
        .searchable(text: $searchText, prompt: "Zoek vergaderingen")
        .sheet(item: $sessionToRename) { session in
            RenameMeetingSheet(session: session) { title in
                storage.renameSession(session, to: title)
            }
        }
        .confirmationDialog("Deze vergadering verwijderen?", isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Verwijder vergadering", role: .destructive) {
                if let sessionToDelete {
                    storage.deleteSession(sessionToDelete)
                    if recorder.latestSessionURL == sessionToDelete.folderURL { recorder.clearLoadedSession() }
                }
                sessionToDelete = nil
            }
            Button("Annuleer", role: .cancel) { sessionToDelete = nil }
        }
    }

    private func load(_ session: MeetingSession) {
        do {
            try recorder.loadSession(session)
        } catch {
            recorder.setStatus("Vergadering kon niet worden geladen: \(error.localizedDescription)")
        }
    }

    private var title: String {
        switch filter {
        case .all: return "Vergaderingen"
        case .transcripts: return "Alle transcripties"
        case .audio: return "Audio-opnames"
        }
    }

    private var subtitle: String {
        switch filter {
        case .all: return "Alles wat je hebt opgenomen, op één rustige plek."
        case .transcripts: return "Alle vergaderingen met een opgeslagen transcriptie."
        case .audio: return "De originele audio van iedere vergadering."
        }
    }
}

private struct CompactMeetingRow: View {
    let session: MeetingSession

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: session.hasTranscript ? "text.quote" : "waveform")
                .foregroundStyle(session.hasTranscript ? .purple : .blue)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                Text(session.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(session.hasTranscript ? "Transcriptie" : "Audio")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }
}

private struct LibraryMeetingRow: View {
    let session: MeetingSession
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    Image(systemName: session.hasTranscript ? "text.quote" : "waveform")
                        .font(.title3)
                        .foregroundStyle(session.hasTranscript ? .purple : .blue)
                        .frame(width: 42, height: 42)
                        .background((session.hasTranscript ? Color.purple : Color.blue).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.headline)
                        Text(session.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().hour().minute()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Text(session.hasTranscript ? "Transcriptie" : "Alleen audio")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Menu {
                Button("Hernoemen", action: onRename)
                Button("Open in Finder") { NSWorkspace.shared.activateFileViewerSelecting([session.folderURL]) }
                if session.hasTranscript {
                    Button("Open transcript") { NSWorkspace.shared.open(session.transcriptURL) }
                }
                Divider()
                Button("Verwijderen", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 14)
    }
}

private struct RecordingHUD: View {
    @Environment(RecordingCoordinator.self) private var recorder
    @Environment(AppStorageManager.self) private var storage

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 11) {
                Circle()
                    .fill(.red)
                    .frame(width: 9, height: 9)
                    .shadow(color: .red.opacity(0.7), radius: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Opname actief")
                        .font(.subheadline.weight(.bold))
                    Text("Microfoon + systeemaudio · \(context.date.formatted(.dateTime.hour().minute().second()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button("Stop") {
                    Task { await recorder.toggleRecording(storage: storage) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: 470)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.red.opacity(0.28), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        }
    }
}

private struct AnimatedWaveform: View {
    let isActive: Bool
    @State private var phase = false
    private let bars: [CGFloat] = [0.25, 0.55, 0.85, 0.42, 0.70, 1.0, 0.50, 0.80, 0.38, 0.63, 0.30, 0.52, 0.25]

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(isActive ? Color.red.gradient : Color.blue.gradient)
                    .frame(width: 7, height: max(10, 66 * height * (phase ? 1 : 0.56)))
                    .animation(.easeInOut(duration: 0.65).delay(Double(index) * 0.035).repeatForever(autoreverses: true), value: phase)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { phase = isActive }
        .onChange(of: isActive) { _, active in phase = active }
    }
}

private struct RenameMeetingSheet: View {
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
                .font(.title3.weight(.bold))
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
        .frame(width: 410)
    }
}

private struct PremiumOnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let features: [(icon: String, color: Color, title: String, text: String)] = [
        ("waveform", .blue, "Opnemen zonder gedoe", "Werkt met Meet, Teams, Zoom en Discord. Je blijft gewoon in je bestaande meeting."),
        ("text.quote", .purple, "Transcriptie die je kunt terugvinden", "Audio, transcriptie en notulen blijven per vergadering bij elkaar."),
        ("lock.shield", .green, "Lokaal en privé", "Je bestanden blijven op je Mac. Jij bepaalt wat je bewaart en wat je verwijdert.")
    ]

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                Text("Welkom bij MeetingNotes")
                    .font(.title2.weight(.bold))
                Spacer()
            }
            let feature = features[page]
            VStack(spacing: 15) {
                Image(systemName: feature.icon)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(feature.color)
                    .frame(width: 88, height: 88)
                    .background(feature.color.opacity(0.12), in: Circle())
                Text(feature.title)
                    .font(.title3.weight(.semibold))
                Text(feature.text)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
            }
            .id(page)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .frame(height: 220)
            HStack(spacing: 7) {
                ForEach(features.indices, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: index == page ? 9 : 7, height: index == page ? 9 : 7)
                }
            }
            HStack {
                Button("Overslaan", action: onFinish)
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
        .frame(width: 560, height: 410)
    }
}
