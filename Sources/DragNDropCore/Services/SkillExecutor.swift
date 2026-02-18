import Foundation
import Logging

// MARK: - Skill Executor

/// Executes skills in parallel to generate companion files
public actor SkillExecutor {
    private let logger = Logger(label: "com.dragndrop.skills.executor")

    private var bundledToolsPath: String?
    private var tempDirectory: URL

    public init() {
        self.tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragNDrop", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
    }

    /// Sets the path to bundled ffmpeg/ffprobe
    public func setBundledToolsPath(_ path: String?) {
        self.bundledToolsPath = path
    }

    // MARK: - Execution

    /// Executes all applicable skills for a file in parallel
    /// Returns companion files that were successfully generated
    public func executeSkills(
        _ skills: [Skill],
        for inputFile: URL,
        progressCallback: (@Sendable (Skill, String) -> Void)? = nil
    ) async -> [CompanionFile] {
        guard !skills.isEmpty else { return [] }

        let fileExtension = inputFile.pathExtension.lowercased()
        let applicableSkills = skills.filter { $0.appliesTo(fileExtension: fileExtension) }

        guard !applicableSkills.isEmpty else {
            logger.info("No applicable skills for file extension: \(fileExtension)")
            return []
        }

        // Create output directory for this execution
        let outputDir = createOutputDirectory(for: inputFile)
        defer { cleanupOutputDirectory(outputDir) }

        logger.info("Executing \(applicableSkills.count) skills for: \(inputFile.lastPathComponent)")

        // Execute skills in parallel
        var companionFiles: [CompanionFile] = []

        await withTaskGroup(of: SkillExecutionResult.self) { group in
            for skill in applicableSkills {
                group.addTask {
                    await self.executeSkill(skill, inputFile: inputFile, outputDir: outputDir)
                }
            }

            for await result in group {
                if let skill = skills.first(where: { $0.id == result.skillId }) {
                    progressCallback?(skill, result.success ? "completed" : "failed")
                }

                if result.success, let outputFile = result.outputFile {
                    // Move file to a stable location before returning
                    if let stableFile = moveToStableLocation(outputFile) {
                        let companion = CompanionFile(
                            url: stableFile,
                            skillId: result.skillId,
                            skillName: result.skillName,
                            outputType: skills.first { $0.id == result.skillId }?.outputType ?? .text
                        )
                        companionFiles.append(companion)
                        logger.info("Skill '\(result.skillName)' completed: \(stableFile.lastPathComponent)")
                    }
                } else if let error = result.error {
                    logger.warning("Skill '\(result.skillName)' failed: \(error)")
                }
            }
        }

        logger.info("Generated \(companionFiles.count) companion files")
        return companionFiles
    }

    /// Executes a single skill for testing purposes
    public func executeSkillForTest(
        _ skill: Skill,
        inputFile: URL,
        outputDir: URL
    ) async -> SkillExecutionResult {
        return await executeSkill(skill, inputFile: inputFile, outputDir: outputDir)
    }

    // MARK: - Private Execution

    private func executeSkill(
        _ skill: Skill,
        inputFile: URL,
        outputDir: URL
    ) async -> SkillExecutionResult {
        let startTime = Date()
        var process: Process?

        do {
            // Write script to temp file
            let scriptPath = outputDir.appendingPathComponent("skill_\(skill.id.uuidString).sh")
            try skill.script.write(to: scriptPath, atomically: true, encoding: .utf8)

            // Make script executable
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

            // Build environment
            var environment = ProcessInfo.processInfo.environment
            environment["INPUT_FILE"] = inputFile.path
            environment["FILENAME"] = inputFile.lastPathComponent
            environment["OUTPUT_DIR"] = outputDir.path

            // Add bundled tools to PATH
            if let toolsPath = bundledToolsPath {
                let currentPath = environment["PATH"] ?? "/usr/bin:/bin"
                environment["PATH"] = "\(toolsPath):\(currentPath)"
                environment["FFMPEG"] = "\(toolsPath)/ffmpeg"
                environment["FFPROBE"] = "\(toolsPath)/ffprobe"
            } else {
                // Try to find system ffmpeg
                environment["FFMPEG"] = "/usr/local/bin/ffmpeg"
                environment["FFPROBE"] = "/usr/local/bin/ffprobe"
            }

            // Create and configure process
            let proc = Process()
            process = proc
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [scriptPath.path]
            proc.environment = environment
            proc.currentDirectoryURL = inputFile.deletingLastPathComponent()

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            proc.standardOutput = outputPipe
            proc.standardError = errorPipe

            // Run with timeout
            let result = try await withTimeout(seconds: skill.timeoutSeconds) {
                try proc.run()
                proc.waitUntilExit()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: outputData, encoding: .utf8) ?? ""
                let stderr = String(data: errorData, encoding: .utf8) ?? ""

                return (proc.terminationStatus, stdout, stderr)
            }

            let duration = Date().timeIntervalSince(startTime)

            // Clean up script
            try? FileManager.default.removeItem(at: scriptPath)

            if result.0 == 0 {
                // Find the output file
                let expectedOutput = findOutputFile(in: outputDir, suffix: skill.outputSuffix, baseName: inputFile.deletingPathExtension().lastPathComponent)

                return SkillExecutionResult(
                    skillId: skill.id,
                    skillName: skill.name,
                    success: expectedOutput != nil,
                    outputFile: expectedOutput,
                    error: expectedOutput == nil ? "Output file not found" : nil,
                    duration: duration,
                    stdout: result.1,
                    stderr: result.2
                )
            } else {
                return SkillExecutionResult(
                    skillId: skill.id,
                    skillName: skill.name,
                    success: false,
                    error: result.2.isEmpty ? "Script exited with code \(result.0)" : result.2,
                    duration: duration,
                    stdout: result.1,
                    stderr: result.2
                )
            }

        } catch is TimeoutError {
            process?.terminate()
            return SkillExecutionResult(
                skillId: skill.id,
                skillName: skill.name,
                success: false,
                error: "Skill timed out after \(skill.timeoutSeconds) seconds",
                duration: Double(skill.timeoutSeconds)
            )
        } catch {
            return SkillExecutionResult(
                skillId: skill.id,
                skillName: skill.name,
                success: false,
                error: error.localizedDescription,
                duration: Date().timeIntervalSince(startTime)
            )
        }
    }

    // MARK: - Helper Methods

    private func createOutputDirectory(for inputFile: URL) -> URL {
        let dirName = "\(inputFile.deletingPathExtension().lastPathComponent)_\(UUID().uuidString.prefix(8))"
        let outputDir = tempDirectory.appendingPathComponent(dirName, isDirectory: true)

        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        return outputDir
    }

    private func cleanupOutputDirectory(_ dir: URL) {
        // Keep files for a bit in case they're still being copied
        // The stable location files will be cleaned up after upload
        DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    private func findOutputFile(in directory: URL, suffix: String, baseName: String) -> URL? {
        let expectedName = baseName + suffix
        let expectedPath = directory.appendingPathComponent(expectedName)

        if FileManager.default.fileExists(atPath: expectedPath.path) {
            return expectedPath
        }

        // Also try to find any file with the suffix
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }

        return contents.first { $0.lastPathComponent.hasSuffix(suffix) }
    }

    private func moveToStableLocation(_ file: URL) -> URL? {
        let stableDir = tempDirectory.appendingPathComponent("completed", isDirectory: true)
        try? FileManager.default.createDirectory(at: stableDir, withIntermediateDirectories: true)

        let stablePath = stableDir.appendingPathComponent(file.lastPathComponent)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: stablePath)

        do {
            try FileManager.default.copyItem(at: file, to: stablePath)
            return stablePath
        } catch {
            logger.error("Failed to move file to stable location: \(error.localizedDescription)")
            return nil
        }
    }

    /// Cleans up completed companion files after upload
    public func cleanupCompanionFile(_ file: CompanionFile) {
        try? FileManager.default.removeItem(at: file.url)
    }

    /// Cleans up all completed companion files
    public func cleanupAllCompleted() {
        let completedDir = tempDirectory.appendingPathComponent("completed", isDirectory: true)
        try? FileManager.default.removeItem(at: completedDir)
    }
}

// MARK: - Timeout Helper

private struct TimeoutError: Error {}

private func withTimeout<T: Sendable>(
    seconds: Int,
    operation: @escaping @Sendable () throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            return try operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            throw TimeoutError()
        }

        guard let result = try await group.next() else {
            throw TimeoutError()
        }

        group.cancelAll()
        return result
    }
}
