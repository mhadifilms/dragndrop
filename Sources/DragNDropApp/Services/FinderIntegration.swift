import Foundation
import AppKit
import DragNDropCore

// MARK: - Finder Integration

/// Handles integration with Finder for right-click uploads
@MainActor
public class FinderIntegration: ObservableObject {
    @Published public var pendingURLs: [URL] = []
    @Published public var isProcessingFinderRequest = false

    public static let shared = FinderIntegration()

    private init() {
        setupURLSchemeHandler()
    }

    // MARK: - URL Scheme Handling

    /// Sets up handling for dragndrop:// URL scheme
    private func setupURLSchemeHandler() {
        // Register for URL scheme events
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            return
        }

        handleURL(url)
    }

    /// Handles incoming URLs from the URL scheme
    public func handleURL(_ url: URL) {
        guard url.scheme == "shotdropper" else { return }

        switch url.host {
        case "upload":
            handleUploadURL(url)
        case "open":
            handleOpenURL(url)
        case "workflow":
            handleWorkflowURL(url)
        default:
            break
        }
    }

    /// Handles dragndrop://upload?file=/path/to/file
    private func handleUploadURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return
        }

        var filePaths: [String] = []

        for item in queryItems {
            if item.name == "file" || item.name == "path", let value = item.value {
                filePaths.append(value)
            }
        }

        if !filePaths.isEmpty {
            let urls = filePaths.map { URL(fileURLWithPath: $0) }
            pendingURLs = urls
            isProcessingFinderRequest = true
        }
    }

    /// Handles dragndrop://open to bring app to front
    private func handleOpenURL(_ url: URL) {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Handles dragndrop://workflow?id=xxx to select a workflow
    private func handleWorkflowURL(_ url: URL) {
        // Implementation for workflow selection via URL
    }

    // MARK: - Services Menu Integration

    /// Registers the app as a Services provider
    public func registerServices() {
        NSApp.servicesProvider = self
    }

    /// Service handler for "Upload with dragndrop" service
    @objc func uploadFilesService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            error.pointee = "No files selected" as NSString
            return
        }

        pendingURLs = urls
        isProcessingFinderRequest = true
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Workflow Export

    /// Exports an Automator workflow for Finder integration
    public func exportAutomatorWorkflow(to url: URL) throws {
        let workflowContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>AMApplicationBuild</key>
            <string>523</string>
            <key>AMApplicationVersion</key>
            <string>2.10</string>
            <key>AMDocumentVersion</key>
            <string>2</string>
            <key>actions</key>
            <array>
                <dict>
                    <key>action</key>
                    <dict>
                        <key>AMAccepts</key>
                        <dict>
                            <key>Container</key>
                            <string>List</string>
                            <key>Optional</key>
                            <false/>
                            <key>Types</key>
                            <array>
                                <string>com.apple.applescript.alias-object</string>
                            </array>
                        </dict>
                        <key>AMActionVersion</key>
                        <string>1.0.2</string>
                        <key>AMApplication</key>
                        <array>
                            <string>Automator</string>
                        </array>
                        <key>AMCategory</key>
                        <string>Files &amp; Folders</string>
                        <key>AMComment</key>
                        <string></string>
                        <key>AMDescription</key>
                        <string>Uploads selected files to S3 using dragndrop</string>
                        <key>AMIconName</key>
                        <string>Run Shell Script</string>
                        <key>AMKeywords</key>
                        <array>
                            <string>shell</string>
                            <string>script</string>
                            <string>command</string>
                            <string>upload</string>
                        </array>
                        <key>AMName</key>
                        <string>Upload with dragndrop</string>
                        <key>AMProvides</key>
                        <dict>
                            <key>Container</key>
                            <string>List</string>
                            <key>Types</key>
                            <array>
                                <string>com.apple.applescript.alias-object</string>
                            </array>
                        </dict>
                        <key>ActionBundlePath</key>
                        <string>/System/Library/Automator/Run Shell Script.action</string>
                        <key>ActionName</key>
                        <string>Run Shell Script</string>
                        <key>ActionParameters</key>
                        <dict>
                            <key>COMMAND_STRING</key>
                            <string>for f in "$@"
        do
            open "dragndrop://upload?file=$f"
        done</string>
                            <key>CheckedForUserDefaultShell</key>
                            <true/>
                            <key>inputMethod</key>
                            <integer>1</integer>
                            <key>shell</key>
                            <string>/bin/zsh</string>
                            <key>source</key>
                            <string></string>
                        </dict>
                    </dict>
                </dict>
            </array>
            <key>connectors</key>
            <dict/>
            <key>workflowMetaData</key>
            <dict>
                <key>workflowTypeIdentifier</key>
                <string>com.apple.Automator.servicesMenu</string>
            </dict>
        </dict>
        </plist>
        """

        try workflowContent.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - AppleScript Support

    /// Generates AppleScript for integration
    public static var appleScriptForUpload: String {
        """
        -- Upload files to dragndrop
        on run {input, parameters}
            set fileList to ""
            repeat with f in input
                set filePath to POSIX path of f
                set fileList to fileList & "file=" & filePath & "&"
            end repeat

            if fileList is not "" then
                set fileList to text 1 thru -2 of fileList
                open location "dragndrop://upload?" & fileList
            end if

            return input
        end run
        """
    }

    // MARK: - Shell Script Integration

    /// Generates shell script for CLI integration
    public static var shellScriptForUpload: String {
        """
        #!/bin/zsh
        # Upload files to dragndrop

        if [ $# -eq 0 ]; then
            echo "Usage: upload-to-shotdropper <file1> [file2] ..."
            exit 1
        fi

        PARAMS=""
        for file in "$@"; do
            ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$file'))")
            PARAMS="$PARAMS&file=$ENCODED"
        done

        # Remove leading &
        PARAMS="${PARAMS:1}"

        open "dragndrop://upload?$PARAMS"
        """
    }
}

// MARK: - Finder Quick Actions

/// Protocol for Quick Action handling
public protocol QuickActionHandler {
    func handleQuickAction(files: [URL], action: String)
}

// MARK: - Drag and Drop from Finder

extension FinderIntegration {
    /// Handles files dropped onto the app icon in Dock
    public func handleDockDrop(_ urls: [URL]) {
        pendingURLs = urls
        isProcessingFinderRequest = true
    }
}

// MARK: - URL Scheme Info

extension FinderIntegration {
    /// Available URL schemes and their documentation
    public static var urlSchemeDocumentation: String {
        """
        dragndrop URL Schemes:

        1. Upload files:
           dragndrop://upload?file=/path/to/file1&file=/path/to/file2

        2. Open app:
           dragndrop://open

        3. Select workflow:
           dragndrop://workflow?id=<workflow-uuid>

        4. Quick upload with workflow:
           dragndrop://upload?file=/path/to/file&workflow=<workflow-name>
        """
    }
}
