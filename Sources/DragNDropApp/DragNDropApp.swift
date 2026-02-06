import SwiftUI
import DragNDropCore

@main
struct dragndropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar extra - the main interface
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appDelegate.appState)
        } label: {
            MenuBarIcon()
                .environmentObject(appDelegate.appState)
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }

        // Hidden window for drag and drop (can be shown)
        Window("dragndrop", id: "main") {
            MainWindowView()
                .environmentObject(appDelegate.appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            dragndropCommands(appState: appDelegate.appState)
        }

        // Onboarding window
        Window("Welcome to dragndrop", id: "onboarding") {
            OnboardingView()
                .environmentObject(appDelegate.appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - Keyboard Commands

struct dragndropCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        // File menu commands
        CommandGroup(after: .newItem) {
            Button("Open Upload Window") {
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .keyboardShortcut("o", modifiers: [.command])

            Divider()

            Button("Pause All Uploads") {
                Task { await appState.pauseUploads() }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!appState.hasActiveUploads)

            Button("Resume All Uploads") {
                Task { await appState.resumeUploads() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!appState.hasActiveUploads)

            Button("Retry All Failed") {
                Task { await appState.retryAllFailed() }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!appState.hasFailedUploads)
        }

        // Edit menu additions
        CommandGroup(after: .pasteboard) {
            Button("Copy S3 URI") {
                if let job = appState.activeJobs.first,
                   let uri = appState.copyS3URI(for: job.id) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(uri, forType: .string)
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(appState.activeJobs.isEmpty)

            Divider()

            Button("Clear Queue") {
                Task { await appState.clearQueue() }
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(appState.pendingJobs.isEmpty)
        }

        // View commands
        CommandGroup(after: .sidebar) {
            Button("Show Upload History") {
                // Open history window
            }
            .keyboardShortcut("h", modifiers: [.command, .option])
        }

        // Help menu additions
        CommandGroup(replacing: .help) {
            Button("dragndrop Help") {
                // Open documentation
            }

            Divider()

            Button("View on GitHub") {
                if let url = URL(string: "https://github.com/dragndrop/dragndrop") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Report an Issue") {
                if let url = URL(string: "https://github.com/dragndrop/dragndrop/issues") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

// MARK: - Menu Bar Icon

struct MenuBarIcon: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: appState.menuBarIconName)
                .symbolRenderingMode(.hierarchical)

            if appState.hasActiveUploads {
                Text("\(appState.activeUploadCount)")
                    .font(.caption2)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let finderIntegration = FinderIntegration.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Always run as menu bar app (no dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Register for Services menu
        finderIntegration.registerServices()

        // Initialize services
        Task {
            await appState.initialize()

            // Show onboarding if needed
            if appState.settings.shouldShowOnboarding {
                await MainActor.run {
                    showOnboarding()
                }
            }
        }
    }

    private func showOnboarding() {
        // Open the onboarding window
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Try to open via window group
            NSApp.sendAction(Selector(("showOnboardingWindow:")), to: nil, from: nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            await appState.shutdown()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep running in menu bar
    }

    // MARK: - URL Scheme Handling

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "dragndrop" {
                finderIntegration.handleURL(url)
            } else if url.isFileURL {
                // Handle direct file drops
                finderIntegration.handleDockDrop([url])
            }
        }

        // Process any pending files from Finder
        if !finderIntegration.pendingURLs.isEmpty {
            Task {
                await appState.processDroppedFiles(finderIntegration.pendingURLs)
                finderIntegration.pendingURLs = []
                finderIntegration.isProcessingFinderRequest = false
            }
        }
    }

    // MARK: - Services Menu

    @objc func uploadFilesService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            error.pointee = "No files selected" as NSString
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        Task {
            await appState.processDroppedFiles(urls)
        }
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    // Published state
    @Published var isAuthenticated = false
    @Published var authState: AuthenticationState = .notAuthenticated
    @Published var uploadStatus: UploadManagerStatus?
    @Published var pendingJobs: [UploadJob] = []
    @Published var activeJobs: [UploadJob] = []
    @Published var droppedItems: [ProcessedItem] = []
    @Published var showingUploadPreview = false
    @Published var showingOnboarding = false
    @Published var isInitialized = false

    // Settings
    @Published var settings: AppSettings = AppSettings.load()

    // Services (internal for Skills UI access)
    internal private(set) var services: ServiceContainer?

    // Computed
    var menuBarIconName: String {
        uploadStatus?.menuBarIcon ?? "tray.and.arrow.up"
    }

    var hasActiveUploads: Bool {
        uploadStatus?.hasActiveUploads ?? false
    }

    var activeUploadCount: Int {
        (uploadStatus?.activeCount ?? 0) + (uploadStatus?.pendingCount ?? 0)
    }

    var statusText: String {
        uploadStatus?.statusText ?? "Ready"
    }

    var hasFailedUploads: Bool {
        uploadStatus?.failedCount ?? 0 > 0
    }

    /// Creates a workflow from current settings (simplified workflow model)
    var currentWorkflow: WorkflowConfiguration {
        WorkflowConfiguration(
            name: "Default",
            bucket: settings.s3Bucket,
            region: settings.awsRegion,
            pathTemplate: PathTemplate(
                template: settings.useCustomUploadPath ? settings.uploadPathPattern : "",
                placeholders: []
            ),
            extractionRules: settings.useCustomUploadPath ? [
                ExtractionRule(
                    name: "Filename Pattern",
                    pattern: settings.filenamePattern,
                    captureGroupMappings: [
                        CaptureGroupMapping(groupIndex: 1, placeholderName: "show"),
                        CaptureGroupMapping(groupIndex: 2, placeholderName: "episode"),
                        CaptureGroupMapping(groupIndex: 3, placeholderName: "shot")
                    ]
                )
            ] : []
        )
    }

    /// Check if ready to upload (bucket configured)
    var isReadyToUpload: Bool {
        !settings.s3Bucket.isEmpty && isAuthenticated
    }

    // MARK: - Initialization

    func initialize() async {
        let container = ServiceContainer()
        self.services = container

        do {
            try await container.initialize()

            // Start CLI server if enabled
            if settings.enableCLIServer {
                try await container.startCLIServer(port: UInt16(settings.cliServerPort))
            }

            // Try to load credentials from profile
            do {
                _ = try await container.authService.loadFromProfile(profileName: settings.awsProfileName)
                authState = await container.authService.authenticationState
                isAuthenticated = authState.isAuthenticated
            } catch {
                // Not logged in yet, that's ok
            }

            // Set up status callback
            await container.uploadManager.setStatusCallback { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.uploadStatus = status
                    self?.activeJobs = status.activeJobs
                }
            }

            // Configure pre-processing with bundled tools
            let toolsPath = Bundle.main.resourceURL?.appendingPathComponent("bin").path
            await container.configurePreProcessing(
                enabled: settings.enablePreProcessing,
                script: settings.preProcessingScript,
                toolsPath: toolsPath
            )

            // Configure skills
            await container.configureSkills(
                enabled: settings.enableSkills,
                toolsPath: toolsPath
            )

            isInitialized = true
        } catch {
            print("Failed to initialize: \(error)")
        }
    }

    func shutdown() async {
        settings.save()
        await services?.stopCLIServer()
    }

    // MARK: - Authentication

    func setCredentials(accessKey: String, secretKey: String, sessionToken: String? = nil, region: String) async throws {
        guard let services = services else {
            throw AppError.notInitialized
        }

        authState = .authenticating

        // Test credentials by making an S3 ListBuckets call
        let creds = AWSCredentials(
            accessKeyId: accessKey,
            secretAccessKey: secretKey,
            sessionToken: sessionToken
        )

        try await services.authService.setDirectCredentials(creds, region: region)

        // Verify they work
        try await services.uploadManager.verifyCredentials(region: region)

        // Save region to settings
        settings.awsRegion = region
        settings.save()

        authState = await services.authService.authenticationState
        isAuthenticated = authState.isAuthenticated
    }

    func signOut() async {
        await services?.authService.signOut()
        authState = .notAuthenticated
        isAuthenticated = false
    }

    // MARK: - File Handling

    func processDroppedFiles(_ urls: [URL]) async {
        guard let services = services else { return }
        guard isReadyToUpload else {
            print("Not ready to upload - check bucket configuration and authentication")
            return
        }

        do {
            let processed = try await services.uploadManager.addFiles(urls: urls, workflow: currentWorkflow, settings: settings)
            droppedItems = processed
            pendingJobs = await services.uploadManager.getPendingJobs()

            if settings.confirmBeforeUpload {
                showingUploadPreview = true
            } else {
                await startUploads()
            }
        } catch {
            print("Error processing files: \(error)")
        }
    }

    func startUploads() async {
        await services?.uploadManager.start()
        showingUploadPreview = false
        droppedItems = []

        if settings.closeWindowAfterUploadStart {
            // Close the main window if open
        }
    }

    func cancelUpload(id: UUID) async {
        await services?.uploadManager.cancelJob(id: id)
    }

    func pauseUploads() async {
        await services?.uploadManager.pause()
    }

    func resumeUploads() async {
        await services?.uploadManager.resume()
    }

    func retryUpload(id: UUID) async {
        await services?.uploadManager.retryJob(id: id)
    }

    func retryAllFailed() async {
        await services?.uploadManager.retryAllFailed()
    }

    func clearQueue() async {
        await services?.uploadManager.clearQueue()
        pendingJobs = []
    }

    // MARK: - Utilities

    func copyS3URI(for jobId: UUID) -> String? {
        let allJobs = pendingJobs + activeJobs
        return allJobs.first(where: { $0.id == jobId })?.fullS3Path
    }

    func openInConsole(jobId: UUID) {
        let allJobs = pendingJobs + activeJobs
        if let url = allJobs.first(where: { $0.id == jobId })?.awsConsoleURL {
            NSWorkspace.shared.open(url)
        }
    }

    func getPresignedURL(for jobId: UUID) async -> String? {
        return try? await services?.uploadManager.getPresignedURL(jobId: jobId)
    }
}

// MARK: - Errors

enum AppError: Error, LocalizedError {
    case notInitialized
    case noActiveWorkflow
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "App not fully initialized"
        case .noActiveWorkflow:
            return "No workflow selected"
        case .authenticationRequired:
            return "Please sign in first"
        }
    }
}
