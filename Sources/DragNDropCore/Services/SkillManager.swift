import Foundation
import Logging

// MARK: - Skill Manager

/// Manages skill persistence and CRUD operations
public actor SkillManager {
    private let logger = Logger(label: "com.dragndrop.skills.manager")

    private var skills: [Skill] = []
    private let storageURL: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("DragNDrop", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        self.storageURL = appFolder.appendingPathComponent("skills.json")
    }

    // MARK: - Loading

    /// Loads skills from disk, merging with built-in skills
    public func load() async {
        var loadedSkills: [Skill] = []

        // Load custom skills from disk
        if FileManager.default.fileExists(atPath: storageURL.path) {
            do {
                let data = try Data(contentsOf: storageURL)
                loadedSkills = try JSONDecoder().decode([Skill].self, from: data)
                logger.info("Loaded \(loadedSkills.count) skills from disk")
            } catch {
                logger.error("Failed to load skills: \(error.localizedDescription)")
            }
        }

        // Merge with built-in skills
        skills = mergeWithBuiltIns(loadedSkills)
        logger.info("Total skills after merge: \(skills.count)")
    }

    /// Merges loaded skills with built-in skills, preserving user modifications to built-ins
    private func mergeWithBuiltIns(_ loadedSkills: [Skill]) -> [Skill] {
        var result: [Skill] = []

        // Add all built-in skills
        for builtIn in Skill.builtInSkills {
            // Check if user has modified this built-in
            if let loaded = loadedSkills.first(where: { $0.id == builtIn.id }) {
                // Preserve user's enabled state and any script modifications
                var merged = builtIn
                merged.enabled = loaded.enabled
                // For built-ins, we keep the latest script from the app
                // but preserve user's enabled state
                result.append(merged)
            } else {
                result.append(builtIn)
            }
        }

        // Add custom skills (non-built-in)
        let customSkills = loadedSkills.filter { !$0.isBuiltIn }
        result.append(contentsOf: customSkills)

        return result
    }

    // MARK: - Saving

    /// Saves all skills to disk
    public func save() async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(skills)
            try data.write(to: storageURL)
            logger.info("Saved \(skills.count) skills to disk")
        } catch {
            logger.error("Failed to save skills: \(error.localizedDescription)")
        }
    }

    // MARK: - CRUD Operations

    /// Gets all skills
    public func getAll() -> [Skill] {
        return skills
    }

    /// Gets only enabled skills
    public func getEnabled() -> [Skill] {
        return skills.filter { $0.enabled }
    }

    /// Gets skills applicable to a specific file extension
    public func getApplicable(forExtension ext: String) -> [Skill] {
        return skills.filter { $0.enabled && $0.appliesTo(fileExtension: ext) }
    }

    /// Gets a skill by ID
    public func get(id: UUID) -> Skill? {
        return skills.first { $0.id == id }
    }

    /// Adds a new custom skill
    public func add(_ skill: Skill) async {
        guard !skill.isBuiltIn else {
            logger.warning("Cannot add a skill marked as built-in")
            return
        }

        var newSkill = skill
        newSkill.isBuiltIn = false
        skills.append(newSkill)
        await save()
        logger.info("Added skill: \(skill.name)")
    }

    /// Updates an existing skill
    public func update(_ skill: Skill) async {
        guard let index = skills.firstIndex(where: { $0.id == skill.id }) else {
            logger.warning("Skill not found for update: \(skill.id)")
            return
        }

        // For built-in skills, only allow updating enabled state
        if skills[index].isBuiltIn {
            var updated = skills[index]
            updated.enabled = skill.enabled
            skills[index] = updated
        } else {
            skills[index] = skill
        }

        await save()
        logger.info("Updated skill: \(skill.name)")
    }

    /// Toggles a skill's enabled state
    public func toggleEnabled(id: UUID) async {
        guard let index = skills.firstIndex(where: { $0.id == id }) else {
            logger.warning("Skill not found for toggle: \(id)")
            return
        }

        skills[index].enabled.toggle()
        await save()
        logger.info("Toggled skill: \(skills[index].name) -> \(skills[index].enabled ? "enabled" : "disabled")")
    }

    /// Deletes a custom skill
    public func delete(id: UUID) async {
        guard let index = skills.firstIndex(where: { $0.id == id }) else {
            logger.warning("Skill not found for deletion: \(id)")
            return
        }

        // Cannot delete built-in skills
        guard !skills[index].isBuiltIn else {
            logger.warning("Cannot delete built-in skill: \(skills[index].name)")
            return
        }

        let name = skills[index].name
        skills.remove(at: index)
        await save()
        logger.info("Deleted skill: \(name)")
    }

    /// Resets a built-in skill to its default state
    public func resetBuiltIn(id: UUID) async {
        guard let builtIn = Skill.builtInSkills.first(where: { $0.id == id }) else {
            logger.warning("Not a built-in skill: \(id)")
            return
        }

        guard let index = skills.firstIndex(where: { $0.id == id }) else {
            logger.warning("Skill not found: \(id)")
            return
        }

        skills[index] = builtIn
        await save()
        logger.info("Reset built-in skill: \(builtIn.name)")
    }

    // MARK: - Validation

    /// Validates a skill's script
    public func validate(script: String) -> (valid: Bool, error: String?) {
        // Basic validation
        guard !script.isEmpty else {
            return (false, "Script cannot be empty")
        }

        // Check for shebang
        guard script.hasPrefix("#!") || script.hasPrefix("#!/") else {
            return (false, "Script should start with a shebang (e.g., #!/bin/bash)")
        }

        // Check for required variable usage
        let usesInputFile = script.contains("$INPUT_FILE") || script.contains("${INPUT_FILE}")
        let usesOutputDir = script.contains("$OUTPUT_DIR") || script.contains("${OUTPUT_DIR}")

        if !usesInputFile {
            return (false, "Script should use $INPUT_FILE variable")
        }

        if !usesOutputDir {
            return (false, "Script should use $OUTPUT_DIR variable for output")
        }

        return (true, nil)
    }

    /// Creates a default template for a new custom skill
    public func createTemplate(name: String, outputSuffix: String) -> String {
        return """
#!/bin/bash
# Custom skill: \(name)
# Available variables:
#   $INPUT_FILE  - Full path to source file
#   $FILENAME    - Just the filename
#   $OUTPUT_DIR  - Directory for skill output
#   $FFMPEG      - Path to bundled ffmpeg
#   $FFPROBE     - Path to bundled ffprobe

set -e

OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME%.*}\(outputSuffix)"

# Add your processing logic here
# Example: "$FFMPEG" -i "$INPUT_FILE" ... "$OUTPUT_FILE"

if [ -f "$OUTPUT_FILE" ]; then
    echo "Output created: $OUTPUT_FILE"
else
    echo "Failed to create output" >&2
    exit 1
fi
"""
    }

    // MARK: - Import/Export

    /// Exports a skill to a file
    public func exportSkill(_ skill: Skill, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(skill)
        try data.write(to: url)
        logger.info("Exported skill '\(skill.name)' to \(url.path)")
    }

    /// Exports multiple skills to a file
    public func exportSkills(_ skillsToExport: [Skill], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(skillsToExport)
        try data.write(to: url)
        logger.info("Exported \(skillsToExport.count) skills to \(url.path)")
    }

    /// Imports a skill from a file
    public func importSkill(from url: URL) async throws -> Skill {
        let data = try Data(contentsOf: url)
        var skill = try JSONDecoder().decode(Skill.self, from: data)

        // Ensure imported skill is not marked as built-in
        skill.isBuiltIn = false

        // Generate new ID to avoid conflicts
        skill.id = UUID()

        // Add the imported skill
        skills.append(skill)
        await save()

        logger.info("Imported skill '\(skill.name)' from \(url.path)")
        return skill
    }

    /// Imports multiple skills from a file
    public func importSkills(from url: URL) async throws -> [Skill] {
        let data = try Data(contentsOf: url)

        // Try to decode as array first
        var importedSkills: [Skill]
        do {
            importedSkills = try JSONDecoder().decode([Skill].self, from: data)
        } catch {
            // Try as single skill
            let single = try JSONDecoder().decode(Skill.self, from: data)
            importedSkills = [single]
        }

        var addedSkills: [Skill] = []
        for var skill in importedSkills {
            // Ensure imported skill is not marked as built-in
            skill.isBuiltIn = false
            // Generate new ID to avoid conflicts
            skill.id = UUID()
            skills.append(skill)
            addedSkills.append(skill)
        }

        await save()
        logger.info("Imported \(addedSkills.count) skills from \(url.path)")
        return addedSkills
    }

    /// Duplicates a skill with a new name
    public func duplicateSkill(id: UUID, newName: String) async -> Skill? {
        guard let original = skills.first(where: { $0.id == id }) else {
            return nil
        }

        var duplicate = original
        duplicate.id = UUID()
        duplicate.name = newName
        duplicate.isBuiltIn = false
        duplicate.enabled = false

        skills.append(duplicate)
        await save()

        logger.info("Duplicated skill '\(original.name)' as '\(newName)'")
        return duplicate
    }
}
