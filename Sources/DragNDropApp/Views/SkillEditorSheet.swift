import SwiftUI
import DragNDropCore

// MARK: - Skill Editor Sheet

struct SkillEditorSheet: View {
    let skill: Skill?
    let onSave: (Skill) -> Void

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var script: String = ""
    @State private var outputSuffix: String = ""
    @State private var outputType: SkillOutputType = .text
    @State private var applicableExtensions: String = ""
    @State private var timeoutSeconds: Int = 300
    @State private var validationError: String?

    private var isBuiltIn: Bool {
        skill?.isBuiltIn ?? false
    }

    private var isEditing: Bool {
        skill != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? (isBuiltIn ? "View Skill" : "Edit Skill") : "Add Custom Skill")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            ScrollView {
                Form {
                    Section("Basic Info") {
                        TextField("Name", text: $name)
                            .disabled(isBuiltIn)

                        TextField("Description", text: $description)
                            .disabled(isBuiltIn)
                    }

                    Section("Output") {
                        TextField("Output suffix (e.g., _thumb.png)", text: $outputSuffix)
                            .font(.system(.body, design: .monospaced))
                            .disabled(isBuiltIn)

                        Picker("Output type", selection: $outputType) {
                            ForEach(SkillOutputType.allCases, id: \.self) { type in
                                Label(type.rawValue, systemImage: type.iconName).tag(type)
                            }
                        }
                        .disabled(isBuiltIn)
                    }

                    Section("File Types") {
                        TextField("Extensions (comma-separated, empty = all)", text: $applicableExtensions)
                            .font(.system(.body, design: .monospaced))
                            .disabled(isBuiltIn)

                        Text("Example: mov, mp4, avi")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Script") {
                        TextEditor(text: $script)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 200)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .disabled(isBuiltIn)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Available variables:")
                                .font(.caption)
                                .fontWeight(.medium)
                            Group {
                                Text("$INPUT_FILE - Full path to source file")
                                Text("$FILENAME - Just the filename")
                                Text("$OUTPUT_DIR - Directory for skill output")
                                Text("$FFMPEG - Path to bundled ffmpeg")
                                Text("$FFPROBE - Path to bundled ffprobe")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Section("Timeout") {
                        Stepper(
                            "Timeout: \(timeoutSeconds) seconds",
                            value: $timeoutSeconds,
                            in: 30...3600,
                            step: 30
                        )
                        .disabled(isBuiltIn)

                        Text("Maximum time allowed for skill execution")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let error = validationError {
                        Section {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .formStyle(.grouped)
            }

            Divider()

            HStack {
                if isBuiltIn {
                    Text("Built-in skills cannot be modified")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !isBuiltIn {
                    Button("Save") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || outputSuffix.isEmpty || script.isEmpty)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadSkill()
        }
    }

    private func loadSkill() {
        if let skill = skill {
            name = skill.name
            description = skill.description
            script = skill.script
            outputSuffix = skill.outputSuffix
            outputType = skill.outputType
            applicableExtensions = skill.applicableExtensions.joined(separator: ", ")
            timeoutSeconds = skill.timeoutSeconds
        } else {
            // Set default template for new skill
            script = defaultScriptTemplate
        }
    }

    private func save() {
        // Validate
        let (valid, error) = validateSkill()
        if !valid {
            validationError = error
            return
        }

        // Parse extensions
        let extensions = applicableExtensions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        let savedSkill = Skill(
            id: skill?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            enabled: skill?.enabled ?? true,
            isBuiltIn: false,
            script: script,
            applicableExtensions: extensions,
            outputSuffix: outputSuffix.trimmingCharacters(in: .whitespaces),
            outputType: outputType,
            timeoutSeconds: timeoutSeconds
        )

        onSave(savedSkill)
        dismiss()
    }

    private func validateSkill() -> (Bool, String?) {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return (false, "Name is required")
        }

        if outputSuffix.trimmingCharacters(in: .whitespaces).isEmpty {
            return (false, "Output suffix is required")
        }

        if script.trimmingCharacters(in: .whitespaces).isEmpty {
            return (false, "Script is required")
        }

        // Check for shebang
        if !script.hasPrefix("#!") {
            return (false, "Script should start with a shebang (e.g., #!/bin/bash)")
        }

        // Check for required variables
        let usesInputFile = script.contains("$INPUT_FILE") || script.contains("${INPUT_FILE}")
        let usesOutputDir = script.contains("$OUTPUT_DIR") || script.contains("${OUTPUT_DIR}")

        if !usesInputFile {
            return (false, "Script should use $INPUT_FILE variable")
        }

        if !usesOutputDir {
            return (false, "Script should use $OUTPUT_DIR for output files")
        }

        return (true, nil)
    }

    private var defaultScriptTemplate: String {
        """
#!/bin/bash
# Custom skill script
# Available variables:
#   $INPUT_FILE  - Full path to source file
#   $FILENAME    - Just the filename
#   $OUTPUT_DIR  - Directory for skill output
#   $FFMPEG      - Path to bundled ffmpeg
#   $FFPROBE     - Path to bundled ffprobe

set -e

OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME%.*}_output.txt"

# Add your processing logic here
# Example: "$FFMPEG" -i "$INPUT_FILE" ... "$OUTPUT_FILE"

echo "Processing: $FILENAME" > "$OUTPUT_FILE"
echo "Completed at: $(date)" >> "$OUTPUT_FILE"

if [ -f "$OUTPUT_FILE" ]; then
    echo "Output created: $OUTPUT_FILE"
else
    echo "Failed to create output" >&2
    exit 1
fi
"""
    }
}

#Preview {
    SkillEditorSheet(skill: nil, onSave: { _ in })
        .environmentObject(AppState())
}
