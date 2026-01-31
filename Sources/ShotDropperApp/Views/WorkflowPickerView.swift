import SwiftUI
import ShotDropperCore

// MARK: - Workflow Picker View

struct WorkflowPickerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var workflows: [WorkflowConfiguration] = []
    @State private var showingNewWorkflow = false
    @State private var showingImport = false
    @State private var searchText = ""

    var filteredWorkflows: [WorkflowConfiguration] {
        if searchText.isEmpty {
            return workflows
        }
        return workflows.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bucket.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search workflows...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()

                Divider()

                // Workflow list
                if workflows.isEmpty {
                    emptyState
                } else {
                    workflowList
                }

                Divider()

                // Footer
                footer
            }
            .frame(width: 450, height: 500)
            .background(.ultraThinMaterial)
            .navigationTitle("Select Workflow")
        }
        .task {
            workflows = await appState.loadWorkflows()
        }
        .sheet(isPresented: $showingNewWorkflow) {
            WorkflowEditorView(workflow: nil)
                .environmentObject(appState)
        }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Workflows")
                .font(.headline)

            Text("Create a workflow to define where your files are uploaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Create Workflow") {
                showingNewWorkflow = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Workflow List

    private var workflowList: some View {
        List(selection: Binding<UUID?>(
            get: { appState.activeWorkflow?.id },
            set: { id in
                if let id = id, let workflow = workflows.first(where: { $0.id == id }) {
                    Task {
                        await appState.setActiveWorkflow(workflow)
                    }
                }
            }
        )) {
            // Presets section
            Section("Quick Start Presets") {
                ForEach(WorkflowConfigurationManager.presets) { preset in
                    WorkflowRow(
                        workflow: preset,
                        isActive: appState.activeWorkflow?.id == preset.id,
                        isPreset: true
                    ) {
                        Task {
                            try? await appState.saveWorkflow(preset)
                            await appState.setActiveWorkflow(preset)
                            dismiss()
                        }
                    }
                }
            }

            // Custom workflows
            if !filteredWorkflows.isEmpty {
                Section("Your Workflows") {
                    ForEach(filteredWorkflows) { workflow in
                        WorkflowRow(
                            workflow: workflow,
                            isActive: appState.activeWorkflow?.id == workflow.id,
                            isPreset: false
                        ) {
                            Task {
                                await appState.setActiveWorkflow(workflow)
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                showingImport = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.plain)

            Spacer()

            Button("Create New") {
                showingNewWorkflow = true
            }

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Actions

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                if let workflow = try? await appState.importWorkflow(from: url) {
                    workflows = await appState.loadWorkflows()
                    await appState.setActiveWorkflow(workflow)
                }
            }
        case .failure(let error):
            print("Import failed: \(error)")
        }
    }
}

// MARK: - Workflow Row

struct WorkflowRow: View {
    let workflow: WorkflowConfiguration
    let isActive: Bool
    let isPreset: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: isPreset ? "star.fill" : "folder.badge.gearshape")
                    .font(.title3)
                    .foregroundStyle(isPreset ? .yellow : .accentColor)
                    .frame(width: 32)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(workflow.name)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if isActive {
                            Text("Active")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.2))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }

                    Text("s3://\(workflow.bucket)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !workflow.description.isEmpty {
                        Text(workflow.description)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Storage provider icon
                Image(systemName: workflow.storageProvider.iconName)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workflow Editor View

struct WorkflowEditorView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let workflow: WorkflowConfiguration?

    @State private var name = ""
    @State private var description = ""
    @State private var bucket = ""
    @State private var region = "us-east-1"
    @State private var pathTemplate = ""
    @State private var extractionPattern = ""
    @State private var showingAdvanced = false

    var isEditing: Bool { workflow != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Info") {
                    TextField("Workflow Name", text: $name)
                    TextField("Description (optional)", text: $description)
                }

                Section("S3 Settings") {
                    TextField("Bucket Name", text: $bucket)

                    Picker("Region", selection: $region) {
                        ForEach(AWSRegion.allRegions, id: \.id) { awsRegion in
                            HStack {
                                Text(awsRegion.flag)
                                Text(awsRegion.name)
                            }
                            .tag(awsRegion.id)
                        }
                    }
                }

                Section("Path Template") {
                    TextField("Template (e.g., {SHOW}/{EPISODE}/{SHOT}/)", text: $pathTemplate)
                        .font(.system(.body, design: .monospaced))

                    Text("Use {PLACEHOLDERS} that will be extracted from filenames")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Extraction Pattern") {
                    TextField("Regex pattern", text: $extractionPattern)
                        .font(.system(.body, design: .monospaced))

                    Text("Capture groups map to placeholders in order")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Advanced Settings", isExpanded: $showingAdvanced) {
                    // File types, transformations, etc.
                    Text("Additional settings coming soon...")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Workflow" : "New Workflow")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveWorkflow()
                    }
                    .disabled(name.isEmpty || bucket.isEmpty)
                }
            }
        }
        .frame(width: 500, height: 600)
        .onAppear {
            if let workflow = workflow {
                name = workflow.name
                description = workflow.description
                bucket = workflow.bucket
                region = workflow.region
                pathTemplate = workflow.pathTemplate.template
                extractionPattern = workflow.extractionRules.first?.pattern ?? ""
            }
        }
    }

    private func saveWorkflow() {
        let newWorkflow = WorkflowConfiguration(
            id: workflow?.id ?? UUID(),
            name: name,
            description: description,
            bucket: bucket,
            region: region,
            pathTemplate: PathTemplate(template: pathTemplate),
            extractionRules: [
                ExtractionRule(
                    name: "Default Pattern",
                    pattern: extractionPattern,
                    captureGroupMappings: []  // Would need UI to configure these
                )
            ]
        )

        Task {
            try? await appState.saveWorkflow(newWorkflow)
            dismiss()
        }
    }
}

#Preview {
    WorkflowPickerView()
        .environmentObject(AppState())
}
