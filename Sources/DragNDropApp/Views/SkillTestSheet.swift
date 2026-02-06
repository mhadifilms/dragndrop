import SwiftUI
import DragNDropCore
import UniformTypeIdentifiers

// MARK: - Skill Test Sheet

struct SkillTestSheet: View {
    let skill: Skill

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState

    @State private var inputFile: URL?
    @State private var isRunning = false
    @State private var result: SkillExecutionResult?
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: skill.iconName)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Test: \(skill.name)")
                        .font(.headline)
                    Text(skill.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Drop zone or file info
            if let inputFile = inputFile {
                // File selected - show info and run button
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(inputFile.lastPathComponent)
                                .font(.headline)
                            Text(inputFile.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button("Clear") {
                            self.inputFile = nil
                            self.result = nil
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Run button
                    Button {
                        runTest()
                    } label: {
                        HStack(spacing: 8) {
                            if isRunning {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 16, height: 16)
                                Text("Running...")
                            } else {
                                Image(systemName: "play.fill")
                                Text("Run Skill")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isRunning)
                }
                .padding()
            } else {
                // Drop zone
                VStack(spacing: 16) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 48))
                        .foregroundStyle(isDragging ? .blue : .secondary)

                    Text("Drop a file here to test")
                        .font(.headline)
                        .foregroundStyle(isDragging ? .primary : .secondary)

                    if !skill.applicableExtensions.isEmpty {
                        Text("Accepts: \(skill.applicableExtensions.map { ".\($0)" }.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Button("Choose File...") {
                        selectInputFile()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isDragging ? Color.blue : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: 2, dash: [8])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isDragging ? Color.blue.opacity(0.05) : Color.clear)
                        )
                )
                .padding()
                .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                    handleDrop(providers: providers)
                }
            }

            // Result section
            if let result = result {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    // Status
                    HStack {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(result.success ? .green : .red)

                        VStack(alignment: .leading) {
                            Text(result.success ? "Success" : "Failed")
                                .font(.headline)
                            Text(String(format: "Completed in %.2fs", result.duration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let outputFile = result.outputFile {
                            Button("Show in Finder") {
                                NSWorkspace.shared.selectFile(
                                    outputFile.path,
                                    inFileViewerRootedAtPath: outputFile.deletingLastPathComponent().path
                                )
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // Error message
                    if let error = result.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    // Output file info
                    if let outputFile = result.outputFile {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.green)
                            Text(outputFile.lastPathComponent)
                                .font(.subheadline)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    // Console output (collapsible)
                    if !result.stdout.isEmpty || !result.stderr.isEmpty {
                        DisclosureGroup("Console Output") {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    if !result.stdout.isEmpty {
                                        Text(result.stdout)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.primary)
                                    }
                                    if !result.stderr.isEmpty {
                                        Text(result.stderr)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.red)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 120)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding()
            }

            Spacer(minLength: 0)
        }
        .frame(width: 480, height: result != nil ? 520 : 380)
    }

    private func selectInputFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a file to test the skill"

        if !skill.applicableExtensions.isEmpty {
            let types = skill.applicableExtensions.compactMap { UTType(filenameExtension: $0) }
            if !types.isEmpty {
                panel.allowedContentTypes = types
            }
        }

        if panel.runModal() == .OK, let url = panel.url {
            inputFile = url
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url = url else { return }

            // Verify extension if skill has restrictions
            if !skill.applicableExtensions.isEmpty {
                let ext = url.pathExtension.lowercased()
                guard skill.applicableExtensions.contains(ext) else { return }
            }

            DispatchQueue.main.async {
                self.inputFile = url
                self.result = nil
            }
        }

        return true
    }

    private func runTest() {
        guard let inputFile = inputFile else { return }
        guard let services = appState.services else { return }

        isRunning = true
        result = nil

        // Use the input file's directory as output directory
        let outputDir = inputFile.deletingLastPathComponent()

        Task {
            let executor = await services.skillExecutor

            if let toolsPath = Bundle.main.resourceURL?.appendingPathComponent("bin").path {
                await executor.setBundledToolsPath(toolsPath)
            }

            let testResult = await executor.executeSkillForTest(skill, inputFile: inputFile, outputDir: outputDir)

            await MainActor.run {
                result = testResult
                isRunning = false
            }
        }
    }
}

#Preview {
    SkillTestSheet(skill: Skill.thumbnailSkill)
        .environmentObject(AppState())
}
