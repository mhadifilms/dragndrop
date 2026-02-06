import SwiftUI
import DragNDropCore

// MARK: - Main Window View

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        NavigationSplitView {
            // Sidebar
            sidebar
        } detail: {
            // Main content
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.05),
                        Color.purple.opacity(0.03),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Content based on selection
                switch selectedTab {
                case 0:
                    dropView
                case 1:
                    uploadsView
                case 2:
                    historyView
                case 3:
                    queueView
                case 4:
                    dashboardView
                default:
                    dropView
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .sheet(isPresented: $appState.showingUploadPreview) {
            UploadPreviewView()
                .environmentObject(appState)
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.space]) { press in
            // Toggle pause/resume with spacebar
            Task {
                if appState.uploadStatus?.isPaused == true {
                    await appState.resumeUploads()
                } else {
                    await appState.pauseUploads()
                }
            }
            return .handled
        }
        // Tab navigation shortcuts (Cmd+1 through Cmd+5)
        .onKeyPress(characters: CharacterSet(charactersIn: "12345"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            switch press.characters {
            case "1": selectedTab = 4  // Dashboard
            case "2": selectedTab = 0  // Drop Zone
            case "3": selectedTab = 1  // Active Uploads
            case "4": selectedTab = 3  // Queue
            case "5": selectedTab = 2  // History
            default: return .ignored
            }
            return .handled
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedTab) {
            Section("Overview") {
                Label("Dashboard", systemImage: "chart.bar.fill")
                    .tag(4)
            }

            Section("Upload") {
                Label("Drop Zone", systemImage: "tray.and.arrow.down.fill")
                    .tag(0)

                Label("Active Uploads", systemImage: "arrow.up.circle.fill")
                    .badge(appState.activeUploadCount)
                    .tag(1)

                Label("Queue", systemImage: "list.bullet.rectangle")
                    .badge(appState.pendingJobs.count)
                    .tag(3)
            }

            Section("History") {
                Label("Recent Uploads", systemImage: "clock.arrow.circlepath")
                    .tag(2)
            }

            Section {
                // Auth status
                HStack {
                    Image(systemName: appState.authState.iconName)
                        .foregroundStyle(appState.isAuthenticated ? .green : .red)
                    Text(appState.isAuthenticated ? "Connected" : "Not signed in")
                        .font(.caption)
                }

                // S3 Bucket
                if !appState.settings.s3Bucket.isEmpty {
                    HStack {
                        Image(systemName: "externaldrive.badge.icloud")
                            .foregroundStyle(.secondary)
                        Text(appState.settings.s3Bucket)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }

    // MARK: - Drop View

    private var dropView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Drop Files to Upload")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                if !appState.settings.s3Bucket.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "externaldrive.badge.icloud")
                        Text("s3://\(appState.settings.s3Bucket)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }

            // Large drop zone
            LargeDropZoneView()
                .environmentObject(appState)
                .frame(maxWidth: 500, maxHeight: 350)

            // Quick tips
            HStack(spacing: 24) {
                TipView(icon: "lightbulb", text: "Drop folders to upload image sequences")
                TipView(icon: "arrow.triangle.branch", text: "Files are auto-organized by shot")
                TipView(icon: "checkmark.shield", text: "Uploads resume if interrupted")
            }
            .padding(.top, 8)
        }
        .padding(40)
    }

    // MARK: - Uploads View

    private var uploadsView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Active Uploads")
                        .font(.title2)
                        .fontWeight(.bold)

                    if let status = appState.uploadStatus {
                        Text(status.statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Controls
                HStack(spacing: 12) {
                    if appState.uploadStatus?.isPaused == true {
                        Button {
                            Task { await appState.resumeUploads() }
                        } label: {
                            Label("Resume All", systemImage: "play.fill")
                        }
                    } else {
                        Button {
                            Task { await appState.pauseUploads() }
                        } label: {
                            Label("Pause All", systemImage: "pause.fill")
                        }
                    }
                }
            }
            .padding()

            Divider()

            // Upload list
            if appState.activeJobs.isEmpty && appState.pendingJobs.isEmpty {
                NoUploadsEmptyState {
                    selectedTab = 0  // Switch to drop zone
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.activeJobs) { job in
                            ActiveUploadCard(job: job)
                                .environmentObject(appState)
                        }

                        if !appState.pendingJobs.isEmpty {
                            Section {
                                ForEach(appState.pendingJobs) { job in
                                    PendingUploadCard(job: job)
                                        .environmentObject(appState)
                                }
                            } header: {
                                HStack {
                                    Text("Queued")
                                        .font(.headline)
                                    Spacer()
                                }
                                .padding(.top, 16)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - History View

    private var historyView: some View {
        UploadHistoryView()
            .environmentObject(appState)
    }

    // MARK: - Queue View

    private var queueView: some View {
        UploadQueueView()
            .environmentObject(appState)
    }

    // MARK: - Dashboard View

    private var dashboardView: some View {
        DashboardView()
            .environmentObject(appState)
    }
}

// MARK: - Upload History View

struct UploadHistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var historyItems: [UploadHistoryItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var filterStatus: UploadStatus? = nil
    @State private var sortOrder: HistorySortOrder = .dateDescending

    enum HistorySortOrder {
        case dateDescending
        case dateAscending
        case sizeDescending
        case sizeAscending
        case nameAscending
    }

    var filteredItems: [UploadHistoryItem] {
        var items = historyItems

        // Filter by search
        if !searchText.isEmpty {
            items = items.filter {
                $0.filename.localizedCaseInsensitiveContains(searchText) ||
                $0.destinationPath.localizedCaseInsensitiveContains(searchText) ||
                $0.bucket.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Filter by status
        if let status = filterStatus {
            items = items.filter { $0.status == status }
        }

        // Sort
        switch sortOrder {
        case .dateDescending:
            items.sort { $0.startedAt > $1.startedAt }
        case .dateAscending:
            items.sort { $0.startedAt < $1.startedAt }
        case .sizeDescending:
            items.sort { $0.fileSize > $1.fileSize }
        case .sizeAscending:
            items.sort { $0.fileSize < $1.fileSize }
        case .nameAscending:
            items.sort { $0.filename < $1.filename }
        }

        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Upload History")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("\(historyItems.count) uploads")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: 200)

                // Filter
                Menu {
                    Button("All") { filterStatus = nil }
                    Divider()
                    Button("Completed") { filterStatus = .completed }
                    Button("Failed") { filterStatus = .failed }
                    Button("Cancelled") { filterStatus = .cancelled }
                } label: {
                    Label(filterStatus?.rawValue.capitalized ?? "All", systemImage: "line.3.horizontal.decrease.circle")
                }

                // Sort
                Menu {
                    Button("Date (Newest)") { sortOrder = .dateDescending }
                    Button("Date (Oldest)") { sortOrder = .dateAscending }
                    Divider()
                    Button("Size (Largest)") { sortOrder = .sizeDescending }
                    Button("Size (Smallest)") { sortOrder = .sizeAscending }
                    Divider()
                    Button("Name") { sortOrder = .nameAscending }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }

                // Clear
                Button {
                    Task {
                        await clearHistory()
                    }
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .foregroundStyle(.red)
                .disabled(historyItems.isEmpty)
            }
            .padding()

            Divider()

            // Content
            if isLoading {
                HistoryListSkeleton()
            } else if filteredItems.isEmpty {
                if !searchText.isEmpty {
                    NoSearchResultsEmptyState(searchText: searchText) {
                        searchText = ""
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    NoHistoryEmptyState()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredItems) { item in
                            HistoryItemRow(item: item)
                        }
                    }
                    .padding()
                }
            }
        }
        .task {
            await loadHistory()
        }
    }

    private func loadHistory() async {
        isLoading = true
        if let services = appState.services {
            historyItems = await services.historyStore.getAll()
        }
        isLoading = false
    }

    private func clearHistory() async {
        if let services = appState.services {
            await services.historyStore.clear()
            await loadHistory()
        }
    }
}

// MARK: - History Item Row

struct HistoryItemRow: View {
    let item: UploadHistoryItem
    @State private var showingDetails = false
    @State private var isHovered = false
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Status icon with animation
                statusIcon
                    .frame(width: 32)
                    .scaleEffect(hasAppeared ? 1.0 : 0.5)

                // File info
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.filename)
                        .font(.headline)
                        .lineLimit(1)

                    Text("s3://\(item.bucket)/\(item.destinationPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Size
                Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Date
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.startedAt, style: .date)
                        .font(.caption)
                    Text(item.startedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Actions
                Menu {
                    Button {
                        copyS3URI()
                    } label: {
                        Label("Copy S3 URI", systemImage: "doc.on.doc")
                    }

                    if let presignedURL = item.presignedURL {
                        Button {
                            copyPresignedURL(presignedURL)
                        } label: {
                            Label("Copy Presigned URL", systemImage: "link")
                        }
                    }

                    Button {
                        openInConsole()
                    } label: {
                        Label("Open in AWS Console", systemImage: "arrow.up.right.square")
                    }

                    Divider()

                    Button {
                        showingDetails = true
                    } label: {
                        Label("Show Details", systemImage: "info.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
            }
            .padding(12)

            // Error message if failed
            if item.status == .failed, let error = item.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(item.status == .failed ? Color.red.opacity(0.05) : (isHovered ? Color.secondary.opacity(0.08) : Color.secondary.opacity(0.05)))
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 10)
        .animation(AnimationPresets.snappy, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            withAnimation(AnimationPresets.spring.delay(Double.random(in: 0...0.1))) {
                hasAppeared = true
            }
        }
        .sheet(isPresented: $showingDetails) {
            HistoryItemDetailView(item: item)
        }
    }

    private var statusIcon: some View {
        Group {
            switch item.status {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .cancelled:
                Image(systemName: "slash.circle.fill")
                    .foregroundStyle(.gray)
            default:
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.title2)
    }

    private func copyS3URI() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.s3URI, forType: .string)
    }

    private func copyPresignedURL(_ url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    private func openInConsole() {
        let urlString = "https://\(item.region).console.aws.amazon.com/s3/object/\(item.bucket)?region=\(item.region)&prefix=\(item.destinationPath)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - History Item Detail View

struct HistoryItemDetailView: View {
    let item: UploadHistoryItem
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("File Information") {
                    LabeledContent("Filename", value: item.filename)
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                    LabeledContent("Source", value: item.sourcePath)
                }

                Section("Upload Details") {
                    LabeledContent("Status", value: item.status.rawValue.capitalized)
                    LabeledContent("Bucket", value: item.bucket)
                    LabeledContent("Region", value: item.region)
                    LabeledContent("Destination", value: item.destinationPath)
                }

                Section("Timestamps") {
                    LabeledContent("Started", value: item.startedAt.formatted())
                    if let completed = item.completedAt {
                        LabeledContent("Completed", value: completed.formatted())
                    }
                    if let duration = item.durationSeconds {
                        LabeledContent("Duration", value: String(format: "%.1f seconds", duration))
                    }
                }

                Section("URLs") {
                    LabeledContent("S3 URI") {
                        Text(item.s3URI)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    if let presignedURL = item.presignedURL {
                        LabeledContent("Presigned URL") {
                            Text(presignedURL)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(2)
                        }
                    }
                }

                if let error = item.errorMessage {
                    Section("Error") {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Upload Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 500, height: 600)
    }
}

// MARK: - Tip View

struct TipView: View {
    let icon: String
    let text: String
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(isHovered ? .primary : .secondary)
                .scaleEffect(isHovered ? 1.1 : 1.0)
            Text(text)
                .font(.caption)
                .foregroundStyle(isHovered ? .primary : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .animation(AnimationPresets.snappy, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Active Upload Card

struct ActiveUploadCard: View {
    @EnvironmentObject var appState: AppState
    let job: UploadJob
    @State private var hasAppeared = false
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Animated icon with progress ring
                ZStack {
                    // Progress ring behind icon
                    Circle()
                        .trim(from: 0, to: job.progress.percentage / 100)
                        .stroke(
                            categoryColor.opacity(0.5),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))
                        .animation(AnimationPresets.smooth, value: job.progress.percentage)

                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 38, height: 38)

                    Image(systemName: job.fileInfo.category.iconName)
                        .font(.title3)
                        .foregroundStyle(categoryColor)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    Text(job.destinationPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Speed and ETA with animated upload arrow
                VStack(alignment: .trailing, spacing: 2) {
                    // Show skill status if running
                    if job.skillStatus.isRunning {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text(job.skillStatus.displayText)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        HStack(spacing: 4) {
                            AnimatedUploadArrow()
                            Text(job.progress.formattedUploadSpeed)
                                .font(.caption)
                                .monospacedDigit()
                        }

                        if let eta = job.progress.formattedTimeRemaining {
                            Text(eta)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Show companion file count if completed
                    if case .completed(let count) = job.skillStatus, count > 0 {
                        Text("+\(count) companion")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                // Cancel button
                Button {
                    Task { await appState.cancelUpload(id: job.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Progress bar with gradient
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [categoryColor, categoryColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * (job.progress.percentage / 100))
                            .animation(AnimationPresets.smooth, value: job.progress.percentage)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("\(job.progress.formattedBytesUploaded) / \(job.progress.formattedTotalBytes)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(String(format: "%.1f%%", job.progress.percentage))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
            }
        }
        .padding(16)
        .background(
            GlassBackground(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(categoryColor.opacity(isHovered ? 0.4 : 0.2), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 20)
        .animation(AnimationPresets.spring, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            withAnimation(AnimationPresets.spring) {
                hasAppeared = true
            }
        }
    }

    private var categoryColor: Color {
        switch job.fileInfo.category {
        case .nukeComp: return .orange
        case .imageSequence: return .purple
        case .video: return .blue
        case .audio: return .green
        case .project: return .yellow
        case .other: return .gray
        }
    }
}

// MARK: - Pending Upload Card

struct PendingUploadCard: View {
    @EnvironmentObject var appState: AppState
    let job: UploadJob

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: job.fileInfo.category.iconName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .font(.subheadline)
                    .lineLimit(1)

                Text(job.fileInfo.formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Queued")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task { await appState.cancelUpload(id: job.id) }
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
        )
    }
}

#Preview {
    MainWindowView()
        .environmentObject(AppState())
}
