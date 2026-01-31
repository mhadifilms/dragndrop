import SwiftUI
import DragNDropCore

// MARK: - Upload Queue View

/// A comprehensive view for managing the upload queue
struct UploadQueueView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedJobs: Set<UUID> = []
    @State private var sortOrder: QueueSortOrder = .priority
    @State private var showingBulkActions = false
    @State private var draggedJob: UploadJob?

    enum QueueSortOrder: String, CaseIterable {
        case priority = "Priority"
        case name = "Name"
        case size = "Size"
        case dateAdded = "Date Added"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            queueHeader

            Divider()

            // Queue content
            if appState.pendingJobs.isEmpty && appState.activeJobs.isEmpty {
                QueueEmptyState()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // Active uploads section
                        if !appState.activeJobs.isEmpty {
                            Section {
                                ForEach(appState.activeJobs) { job in
                                    QueueJobCard(
                                        job: job,
                                        isSelected: selectedJobs.contains(job.id),
                                        isActive: true
                                    ) {
                                        toggleSelection(job.id)
                                    }
                                }
                            } header: {
                                QueueSectionHeader(
                                    title: "Uploading",
                                    count: appState.activeJobs.count,
                                    icon: "arrow.up.circle.fill",
                                    color: .blue
                                )
                            }
                        }

                        // Pending uploads section
                        if !appState.pendingJobs.isEmpty {
                            Section {
                                ForEach(sortedPendingJobs) { job in
                                    QueueJobCard(
                                        job: job,
                                        isSelected: selectedJobs.contains(job.id),
                                        isActive: false
                                    ) {
                                        toggleSelection(job.id)
                                    }
                                }
                            } header: {
                                QueueSectionHeader(
                                    title: "Queued",
                                    count: appState.pendingJobs.count,
                                    icon: "clock.fill",
                                    color: .secondary
                                )
                            }
                        }
                    }
                    .padding()
                }
            }

            // Bulk actions bar
            if !selectedJobs.isEmpty {
                bulkActionsBar
            }
        }
    }

    // MARK: - Header

    private var queueHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Upload Queue")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(queueSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Sort picker
            Picker("Sort", selection: $sortOrder) {
                ForEach(QueueSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            // Select all / Deselect
            Button {
                if selectedJobs.count == totalJobCount {
                    selectedJobs.removeAll()
                } else {
                    selectedJobs = Set(appState.activeJobs.map(\.id) + appState.pendingJobs.map(\.id))
                }
            } label: {
                Image(systemName: selectedJobs.count == totalJobCount ? "checkmark.square.fill" : "square")
            }
            .buttonStyle(.plain)
            .tooltip(selectedJobs.isEmpty ? "Select All" : "Deselect All")

            // Pause / Resume all
            if appState.uploadStatus?.isPaused == true {
                Button {
                    Task { await appState.resumeUploads() }
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.bordered)
                .tooltip("Resume All")
            } else {
                Button {
                    Task { await appState.pauseUploads() }
                } label: {
                    Image(systemName: "pause.fill")
                }
                .buttonStyle(.bordered)
                .tooltip("Pause All")
            }
        }
        .padding()
    }

    // MARK: - Bulk Actions Bar

    private var bulkActionsBar: some View {
        HStack {
            Text("\(selectedJobs.count) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                // Move to front
                moveSelectedToFront()
            } label: {
                Label("Move to Front", systemImage: "arrow.up.to.line")
            }
            .buttonStyle(.bordered)
            .disabled(selectedJobs.isEmpty)

            Button {
                // Move to back
                moveSelectedToBack()
            } label: {
                Label("Move to Back", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.bordered)
            .disabled(selectedJobs.isEmpty)

            Button(role: .destructive) {
                // Cancel selected
                cancelSelected()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .disabled(selectedJobs.isEmpty)
        }
        .padding()
        .background(.ultraThinMaterial)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Computed Properties

    private var sortedPendingJobs: [UploadJob] {
        switch sortOrder {
        case .priority:
            return appState.pendingJobs
        case .name:
            return appState.pendingJobs.sorted { $0.displayName < $1.displayName }
        case .size:
            return appState.pendingJobs.sorted { $0.fileInfo.size > $1.fileInfo.size }
        case .dateAdded:
            return appState.pendingJobs.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private var totalJobCount: Int {
        appState.activeJobs.count + appState.pendingJobs.count
    }

    private var queueSummary: String {
        let active = appState.activeJobs.count
        let pending = appState.pendingJobs.count
        let totalSize = (appState.activeJobs + appState.pendingJobs).reduce(0) { $0 + $1.fileInfo.size }

        if active == 0 && pending == 0 {
            return "Queue is empty"
        }

        var parts: [String] = []
        if active > 0 {
            parts.append("\(active) uploading")
        }
        if pending > 0 {
            parts.append("\(pending) queued")
        }
        parts.append(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))

        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private func toggleSelection(_ id: UUID) {
        if selectedJobs.contains(id) {
            selectedJobs.remove(id)
        } else {
            selectedJobs.insert(id)
        }
    }

    private func moveSelectedToFront() {
        // Implementation would reorder queue
        selectedJobs.removeAll()
    }

    private func moveSelectedToBack() {
        // Implementation would reorder queue
        selectedJobs.removeAll()
    }

    private func cancelSelected() {
        for jobId in selectedJobs {
            Task {
                await appState.cancelUpload(id: jobId)
            }
        }
        selectedJobs.removeAll()
    }
}

// MARK: - Queue Section Header

struct QueueSectionHeader: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)

            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("(\(count))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Queue Job Card

struct QueueJobCard: View {
    let job: UploadJob
    let isSelected: Bool
    let isActive: Bool
    let onSelect: () -> Void

    @State private var isHovered = false
    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox
            Button(action: onSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            // File icon with category color
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: job.fileInfo.category.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(categoryColor)
            }

            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(job.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(ByteCountFormatter.string(fromByteCount: job.fileInfo.size, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isActive {
                        Text("·")
                            .foregroundStyle(.tertiary)

                        Text(String(format: "%.0f%%", job.progress.percentage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Spacer()

            // Status indicator
            if isActive {
                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                        .frame(width: 32, height: 32)

                    Circle()
                        .trim(from: 0, to: job.progress.percentage / 100)
                        .stroke(categoryColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))

                    Image(systemName: "arrow.up")
                        .font(.caption)
                        .foregroundStyle(categoryColor)
                }
            } else {
                // Queue position badge
                Text("#\(queuePosition)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Actions menu
            Menu {
                if isActive {
                    Button {
                        Task { await pauseJob() }
                    } label: {
                        Label("Pause", systemImage: "pause")
                    }
                } else {
                    Button {
                        // Move to front
                    } label: {
                        Label("Move to Front", systemImage: "arrow.up.to.line")
                    }

                    Button {
                        // Start immediately
                    } label: {
                        Label("Start Now", systemImage: "play")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    Task { await cancelJob() }
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .opacity(hasAppeared ? 1 : 0)
        .offset(x: hasAppeared ? 0 : -10)
        .animation(AnimationPresets.snappy, value: isHovered)
        .animation(AnimationPresets.snappy, value: isSelected)
        .onHover { isHovered = $0 }
        .onAppear {
            withAnimation(AnimationPresets.spring.delay(Double.random(in: 0...0.1))) {
                hasAppeared = true
            }
        }
    }

    private var categoryColor: Color {
        switch job.fileInfo.category {
        case .nukeComp: return .purple
        case .imageSequence: return .blue
        case .video: return .pink
        case .audio: return .orange
        case .project: return .green
        case .other: return .secondary
        }
    }

    private var queuePosition: Int {
        // This would be computed based on actual queue position
        1
    }

    private func pauseJob() async {
        // Implementation
    }

    private func cancelJob() async {
        // Implementation
    }
}

// MARK: - Compact Queue Widget

/// A compact queue widget for the menu bar
struct CompactQueueWidget: View {
    @EnvironmentObject var appState: AppState
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 8) {
            // Summary header
            Button {
                withAnimation(AnimationPresets.snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    // Progress indicator
                    if let status = appState.uploadStatus, status.isRunning {
                        CircularProgressRing(progress: status.overallProgress / 100, size: 24)
                    } else {
                        Image(systemName: "tray.and.arrow.up")
                            .font(.title3)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(queueTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(queueSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(appState.activeJobs.prefix(3)) { job in
                        CompactJobRow(job: job)
                    }

                    if appState.activeJobs.count > 3 {
                        Text("+ \(appState.activeJobs.count - 3) more...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var queueTitle: String {
        let total = appState.activeJobs.count + appState.pendingJobs.count
        if total == 0 {
            return "No uploads"
        } else if appState.uploadStatus?.isPaused == true {
            return "Uploads paused"
        } else {
            return "\(appState.activeJobs.count) uploading"
        }
    }

    private var queueSubtitle: String {
        if appState.pendingJobs.isEmpty {
            return "Queue is empty"
        } else {
            return "\(appState.pendingJobs.count) in queue"
        }
    }
}

// MARK: - Compact Job Row

struct CompactJobRow: View {
    let job: UploadJob

    var body: some View {
        HStack(spacing: 8) {
            // Mini progress ring
            CircularProgressRing(progress: job.progress.percentage / 100, size: 18)

            Text(job.displayName)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Text(String(format: "%.0f%%", job.progress.percentage))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Circular Progress Ring

struct CircularProgressRing: View {
    let progress: Double
    let size: CGFloat
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(AnimationPresets.smooth, value: progress)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#Preview("Upload Queue") {
    UploadQueueView()
        .environmentObject(AppState())
        .frame(width: 500, height: 600)
}

#Preview("Compact Widget") {
    CompactQueueWidget()
        .environmentObject(AppState())
        .frame(width: 300)
        .padding()
}
