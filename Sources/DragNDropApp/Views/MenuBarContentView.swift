import SwiftUI
import DragNDropCore

// MARK: - Menu Bar Content View

struct MenuBarContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var showingQuickSettings = false
    @State private var showingWorkflowPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()
                .padding(.horizontal)

            // Main content
            if !appState.isAuthenticated {
                authenticationPrompt
            } else if appState.activeWorkflow == nil {
                workflowPrompt
            } else {
                mainContent
            }

            Divider()
                .padding(.horizontal)

            // Footer
            footerSection
        }
        .frame(width: 380)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            // App icon and status
            HStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.up.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("dragndrop")
                        .font(.headline)

                    Text(appState.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Settings button
            Button {
                showingQuickSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingQuickSettings) {
                QuickSettingsView(openSettingsAction: openSettingsWindow)
                    .environmentObject(appState)
            }
        }
        .padding()
    }

    private func openSettingsWindow() {
        showingQuickSettings = false
        // Dispatch to next run loop to ensure popover closes first
        DispatchQueue.main.async {
            openSettings()
            // Force app activation and bring Settings to front
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSApp.activate(ignoringOtherApps: true)
                // Find and focus the Settings window
                for window in NSApp.windows {
                    if window.title.contains("Settings") || window.identifier?.rawValue.contains("settings") == true {
                        window.makeKeyAndOrderFront(nil)
                        break
                    }
                }
            }
        }
    }

    // MARK: - Authentication Prompt

    private var authenticationPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .pulse(duration: 2.0)

            Text("AWS Credentials Required")
                .font(.headline)
                .animatedAppearance(delay: 0.1)

            Text("Add your AWS access key and secret in Settings to start uploading files to S3.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .animatedAppearance(delay: 0.2)

            Button("Open Settings") {
                openSettingsWindow()
            }
            .buttonStyle(.borderedProminent)
            .animatedAppearance(delay: 0.3)
        }
        .padding(24)
    }

    // MARK: - Workflow Prompt

    private var workflowPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .pulse(duration: 2.0)

            Text("Select a Workflow")
                .font(.headline)
                .animatedAppearance(delay: 0.1)

            Text("Choose or create a workflow to define where files are uploaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .animatedAppearance(delay: 0.2)

            Button("Choose Workflow") {
                showingWorkflowPicker = true
            }
            .buttonStyle(.borderedProminent)
            .animatedAppearance(delay: 0.3)
        }
        .padding(24)
        .sheet(isPresented: $showingWorkflowPicker) {
            WorkflowPickerView()
                .environmentObject(appState)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 12) {
            // Workflow info
            workflowInfoSection

            // Drop zone
            DropZoneView()
                .environmentObject(appState)
                .frame(height: 140)
                .padding(.horizontal)

            // Active uploads
            if appState.hasActiveUploads {
                activeUploadsSection
            }
        }
        .padding(.vertical, 12)
    }

    private var workflowInfoSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.activeWorkflow?.name ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("s3://\(appState.activeWorkflow?.bucket ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showingWorkflowPicker = true
            } label: {
                Text("Change")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .padding(.horizontal)
        .sheet(isPresented: $showingWorkflowPicker) {
            WorkflowPickerView()
                .environmentObject(appState)
        }
    }

    private var activeUploadsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Active Uploads")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if let status = appState.uploadStatus, status.isRunning {
                    Button {
                        Task { await appState.pauseUploads() }
                    } label: {
                        Image(systemName: "pause.circle")
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        Task { await appState.resumeUploads() }
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.plain)
                }
            }

            // Progress bar
            if let status = appState.uploadStatus {
                VStack(spacing: 4) {
                    ProgressView(value: status.overallProgress, total: 100)
                        .progressViewStyle(.linear)

                    HStack {
                        Text("\(status.activeCount) uploading")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(String(format: "%.1f%%", status.overallProgress))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Job list (max 3)
            ForEach(appState.activeJobs.prefix(3)) { job in
                UploadJobRow(job: job)
            }

            if appState.activeJobs.count > 3 {
                Text("+ \(appState.activeJobs.count - 3) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            // Auth status
            HStack(spacing: 4) {
                Image(systemName: appState.authState.iconName)
                    .font(.caption)
                Text(appState.isAuthenticated ? "Connected" : "Not signed in")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

}

// MARK: - Upload Job Row

struct UploadJobRow: View {
    let job: UploadJob
    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: 8) {
            // Animated upload icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 24, height: 24)

                Image(systemName: job.fileInfo.category.iconName)
                    .font(.caption)
                    .foregroundStyle(categoryColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .font(.caption)
                    .lineLimit(1)

                // Custom progress bar with gradient
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.2))

                        RoundedRectangle(cornerRadius: 2)
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
                .frame(height: 4)
            }

            Text(String(format: "%.0f%%", job.progress.percentage))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .opacity(hasAppeared ? 1 : 0)
        .offset(x: hasAppeared ? 0 : -10)
        .onAppear {
            withAnimation(AnimationPresets.snappy) {
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

// MARK: - Quick Settings View

struct QuickSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    var openSettingsAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Settings")
                .font(.headline)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Auto-start uploads", isOn: $appState.settings.autoStartUploads)

                    Toggle("Confirm before upload", isOn: $appState.settings.confirmBeforeUpload)

                    Toggle("Notifications", isOn: $appState.settings.showNotifications)
                }
                .toggleStyle(.switch)
            }

            GroupBox("Upload Settings") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Concurrent uploads:")
                        Spacer()
                        Stepper("\(appState.settings.defaultUploadSettings.maxConcurrentUploads)",
                               value: $appState.settings.defaultUploadSettings.maxConcurrentUploads,
                               in: 1...8)
                    }
                }
            }

            HStack {
                Spacer()

                Button("Open Settings...") {
                    openSettingsAction()
                }

                Button("Done") {
                    appState.settings.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

#Preview {
    MenuBarContentView()
        .environmentObject(AppState())
}
