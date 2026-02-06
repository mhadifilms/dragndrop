import SwiftUI
import DragNDropCore

// MARK: - Upload Preview View

struct UploadPreviewView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var selectedItems: Set<UUID> = []
    @State private var editingDestination: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // File list
            if appState.droppedItems.isEmpty {
                emptyState
            } else {
                fileList
            }

            Divider()

            // Footer with actions
            footer
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(.ultraThinMaterial)
        .onAppear {
            // Select all by default
            selectedItems = Set(appState.droppedItems.compactMap { $0.job?.id })
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Upload Preview")
                    .font(.headline)

                Text("\(appState.droppedItems.count) item\(appState.droppedItems.count == 1 ? "" : "s") ready to upload")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Destination bucket info
            if !appState.settings.s3Bucket.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .foregroundStyle(.secondary)

                    Text("s3://\(appState.settings.s3Bucket)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.quaternary)
                .clipShape(Capsule())
            }
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No files to upload")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File List

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(appState.droppedItems, id: \.url) { item in
                    if let job = item.job {
                        UploadPreviewRow(
                            job: job,
                            isSelected: selectedItems.contains(job.id),
                            isEditing: editingDestination == job.id,
                            onToggle: { toggleSelection(job.id) },
                            onEditDestination: { editingDestination = job.id },
                            onDestinationChanged: { newPath in
                                updateDestination(jobId: job.id, newPath: newPath)
                            }
                        )
                    } else {
                        // Error item
                        UploadErrorRow(url: item.url, error: item.error ?? "Unknown error")
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            // Selection controls
            HStack(spacing: 12) {
                Button("Select All") {
                    selectedItems = Set(appState.droppedItems.compactMap { $0.job?.id })
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Select None") {
                    selectedItems.removeAll()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Total size
            let totalSize = appState.droppedItems
                .compactMap { $0.job?.fileInfo.size }
                .reduce(0, +)
            Text("Total: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Upload \(selectedItems.count) File\(selectedItems.count == 1 ? "" : "s")") {
                    Task {
                        await startUpload()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedItems.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func toggleSelection(_ id: UUID) {
        if selectedItems.contains(id) {
            selectedItems.remove(id)
        } else {
            selectedItems.insert(id)
        }
    }

    private func updateDestination(jobId: UUID, newPath: String) {
        // Update job destination
        editingDestination = nil
    }

    private func startUpload() async {
        // Remove unselected items from pending
        for item in appState.droppedItems {
            if let job = item.job, !selectedItems.contains(job.id) {
                await appState.cancelUpload(id: job.id)
            }
        }

        await appState.startUploads()
        dismiss()
    }
}

// MARK: - Upload Preview Row

struct UploadPreviewRow: View {
    let job: UploadJob
    let isSelected: Bool
    let isEditing: Bool
    let onToggle: () -> Void
    let onEditDestination: () -> Void
    let onDestinationChanged: (String) -> Void

    @State private var editedPath: String = ""
    @State private var isHovered = false
    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: 12) {
            // Animated checkbox
            Button {
                onToggle()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .scaleEffect(isSelected ? 1.1 : 1.0)
                    .animation(AnimationPresets.bouncy, value: isSelected)
            }
            .buttonStyle(.plain)

            // File icon
            Image(systemName: job.fileInfo.category.iconName)
                .font(.title3)
                .foregroundStyle(categoryColor)
                .frame(width: 32)

            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(job.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if isEditing {
                    TextField("Destination path", text: $editedPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit {
                            onDestinationChanged(editedPath)
                        }
                        .onAppear {
                            editedPath = job.destinationPath
                        }
                } else {
                    HStack(spacing: 4) {
                        Text(job.destinationPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Button {
                            onEditDestination()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

                // Extracted values
                if !job.extractedValues.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(job.extractedValues.keys.prefix(4)), id: \.self) { key in
                            HStack(spacing: 2) {
                                Text(key)
                                    .foregroundStyle(.secondary)
                                Text(job.extractedValues[key] ?? "")
                            }
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer()

            // File size
            Text(job.fileInfo.formattedSize)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color.secondary.opacity(0.05) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : (isHovered ? Color.secondary.opacity(0.2) : Color.clear), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .opacity(hasAppeared ? 1 : 0)
        .offset(x: hasAppeared ? 0 : -20)
        .animation(AnimationPresets.snappy, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            withAnimation(AnimationPresets.spring.delay(Double.random(in: 0...0.2))) {
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

// MARK: - Upload Error Row

struct UploadErrorRow: View {
    let url: URL
    let error: String
    @State private var shakeOnAppear = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.red)
                .frame(width: 44)
                .pulse(duration: 1.5)

            VStack(alignment: .leading, spacing: 4) {
                Text(url.lastPathComponent)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
        )
        .shake(trigger: shakeOnAppear)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                shakeOnAppear.toggle()
            }
        }
    }
}

#Preview {
    UploadPreviewView()
        .environmentObject(AppState())
}
