import SwiftUI
import DragNDropCore
import UniformTypeIdentifiers

// MARK: - Skills Settings View

struct SkillsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var skills: [Skill] = []
    @State private var showingAddSkill = false
    @State private var editingSkill: Skill?
    @State private var testingSkill: Skill?
    @State private var showingDuplicateAlert = false
    @State private var selectedSkill: Skill?
    @State private var isLoading = true
    @State private var duplicateName = ""
    @State private var importError: String?
    @State private var showingImportError = false

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Skills")
                            .font(.headline)
                        Text("Generate companion files with your uploads")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button {
                            importSkills()
                        } label: {
                            Label("Import Skills...", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            exportAllCustomSkills()
                        } label: {
                            Label("Export Custom Skills...", systemImage: "square.and.arrow.up")
                        }
                        .disabled(skills.filter { !$0.isBuiltIn }.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 30)
                }
            }

            Section("Built-in Skills") {
                ForEach(skills.filter { $0.isBuiltIn }) { skill in
                    SkillRowView(
                        skill: skill,
                        onToggle: { toggleSkill(skill) },
                        onEdit: { editingSkill = skill },
                        onTest: { testingSkill = skill },
                        onDuplicate: { prepareDuplicate(skill) },
                        onExport: { exportSkill(skill) },
                        onDelete: nil
                    )
                }
            }

            if !skills.filter({ !$0.isBuiltIn }).isEmpty {
                Section("Custom Skills") {
                    ForEach(skills.filter { !$0.isBuiltIn }) { skill in
                        SkillRowView(
                            skill: skill,
                            onToggle: { toggleSkill(skill) },
                            onEdit: { editingSkill = skill },
                            onTest: { testingSkill = skill },
                            onDuplicate: { prepareDuplicate(skill) },
                            onExport: { exportSkill(skill) },
                            onDelete: { deleteSkill(skill) }
                        )
                    }
                }
            }

            Section {
                Button {
                    showingAddSkill = true
                } label: {
                    Label("Add Custom Skill", systemImage: "plus.circle")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadSkills()
        }
        .sheet(isPresented: $showingAddSkill) {
            SkillEditorSheet(skill: nil, onSave: addSkill)
        }
        .sheet(item: $editingSkill) { skill in
            SkillEditorSheet(skill: skill, onSave: updateSkill)
        }
        .sheet(item: $testingSkill) { skill in
            SkillTestSheet(skill: skill)
                .environmentObject(appState)
        }
        .alert("Duplicate Skill", isPresented: $showingDuplicateAlert) {
            TextField("New skill name", text: $duplicateName)
            Button("Cancel", role: .cancel) { }
            Button("Duplicate") {
                duplicateSkill()
            }
            .disabled(duplicateName.isEmpty)
        } message: {
            Text("Enter a name for the duplicated skill")
        }
        .alert("Import Error", isPresented: $showingImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importError ?? "Failed to import skills")
        }
    }

    private func loadSkills() {
        Task {
            guard let services = appState.services else { return }
            let loadedSkills = await services.skillManager.getAll()
            await MainActor.run {
                skills = loadedSkills
                isLoading = false
            }
        }
    }

    private func toggleSkill(_ skill: Skill) {
        Task {
            guard let services = appState.services else { return }
            await services.skillManager.toggleEnabled(id: skill.id)
            loadSkills()
        }
    }

    private func addSkill(_ skill: Skill) {
        Task {
            guard let services = appState.services else { return }
            await services.skillManager.add(skill)
            loadSkills()
        }
    }

    private func updateSkill(_ skill: Skill) {
        Task {
            guard let services = appState.services else { return }
            await services.skillManager.update(skill)
            loadSkills()
        }
    }

    private func deleteSkill(_ skill: Skill) {
        Task {
            guard let services = appState.services else { return }
            await services.skillManager.delete(id: skill.id)
            loadSkills()
        }
    }

    private func prepareDuplicate(_ skill: Skill) {
        selectedSkill = skill
        duplicateName = "\(skill.name) Copy"
        showingDuplicateAlert = true
    }

    private func duplicateSkill() {
        guard let skill = selectedSkill else { return }
        Task {
            guard let services = appState.services else { return }
            _ = await services.skillManager.duplicateSkill(id: skill.id, newName: duplicateName)
            loadSkills()
        }
    }

    private func exportSkill(_ skill: Skill) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(skill.name).dragndropskill"
        panel.allowedContentTypes = [UTType(filenameExtension: "dragndropskill") ?? .json]

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                guard let services = appState.services else { return }
                do {
                    try await services.skillManager.exportSkill(skill, to: url)
                } catch {
                    await MainActor.run {
                        importError = error.localizedDescription
                        showingImportError = true
                    }
                }
            }
        }
    }

    private func exportAllCustomSkills() {
        let customSkills = skills.filter { !$0.isBuiltIn }
        guard !customSkills.isEmpty else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "custom_skills.dragndropskills"
        panel.allowedContentTypes = [UTType(filenameExtension: "dragndropskills") ?? .json]

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                guard let services = appState.services else { return }
                do {
                    try await services.skillManager.exportSkills(customSkills, to: url)
                } catch {
                    await MainActor.run {
                        importError = error.localizedDescription
                        showingImportError = true
                    }
                }
            }
        }
    }

    private func importSkills() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "dragndropskill") ?? .json,
            UTType(filenameExtension: "dragndropskills") ?? .json,
            .json
        ]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                guard let services = appState.services else { return }
                do {
                    _ = try await services.skillManager.importSkills(from: url)
                    loadSkills()
                } catch {
                    await MainActor.run {
                        importError = error.localizedDescription
                        showingImportError = true
                    }
                }
            }
        }
    }
}

// MARK: - Skill Row View

struct SkillRowView: View {
    let skill: Skill
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onTest: () -> Void
    let onDuplicate: () -> Void
    let onExport: () -> Void
    let onDelete: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Enable toggle
            Button {
                onToggle()
            } label: {
                Image(systemName: skill.enabled ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(skill.enabled ? .green : .secondary)
            }
            .buttonStyle(.plain)

            // Skill icon (SF Symbol, no emoji)
            Image(systemName: skill.iconName)
                .font(.title3)
                .foregroundStyle(skill.enabled ? .primary : .secondary)
                .frame(width: 24)

            // Skill info
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(skill.enabled ? .primary : .secondary)

                Text(skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !skill.applicableExtensions.isEmpty {
                    Text(skill.applicableExtensions.prefix(5).map { ".\($0)" }.joined(separator: " ") +
                         (skill.applicableExtensions.count > 5 ? " +\(skill.applicableExtensions.count - 5)" : ""))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    onTest()
                } label: {
                    Image(systemName: "play.circle")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Test skill")

                Button {
                    onEdit()
                } label: {
                    Image(systemName: skill.isBuiltIn ? "eye" : "pencil")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(skill.isBuiltIn ? "View skill" : "Edit skill")

                Menu {
                    Button {
                        onDuplicate()
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }

                    Button {
                        onExport()
                    } label: {
                        Label("Export...", systemImage: "square.and.arrow.up")
                    }

                    if let onDelete = onDelete {
                        Divider()
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            .opacity(isHovering ? 1 : 0.6)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

#Preview {
    SkillsSettingsView()
        .environmentObject(AppState())
        .frame(width: 550, height: 500)
}
