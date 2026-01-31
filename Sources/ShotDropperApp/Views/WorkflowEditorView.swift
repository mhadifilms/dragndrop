import SwiftUI
import ShotDropperCore

// MARK: - Visual Workflow Editor View

struct VisualWorkflowEditorView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var workflow: WorkflowConfiguration
    @State private var showingPreview = false
    @State private var previewFilename = "SHO_EP101_SH0010_comp_v001.nk"

    let isNew: Bool
    let onSave: (WorkflowConfiguration) async throws -> Void

    init(
        workflow: WorkflowConfiguration? = nil,
        onSave: @escaping (WorkflowConfiguration) async throws -> Void
    ) {
        self.isNew = workflow == nil
        self._workflow = State(initialValue: workflow ?? WorkflowConfiguration(
            name: "New Workflow",
            bucket: "",
            region: "us-east-1",
            pathTemplate: PathTemplate(template: "{show}/{episode}/{shot}/"),
            extractionRules: []
        ))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                // Basic Info Section
                Section("Basic Information") {
                    TextField("Workflow Name", text: $workflow.name)

                    TextField("S3 Bucket", text: $workflow.bucket)
                        .textFieldStyle(.roundedBorder)

                    Picker("Region", selection: $workflow.region) {
                        ForEach(ShotDropperCore.AWSRegion.allRegions, id: \.id) { region in
                            HStack {
                                Text(region.flag)
                                Text(region.name)
                            }
                            .tag(region.id)
                        }
                    }
                }

                // Path Template Section
                Section("Destination Path") {
                    PathTemplateEditor(template: $workflow.pathTemplate)
                }

                // Extraction Rules Section
                Section("Filename Extraction Rules") {
                    ExtractionRulesEditor(rules: $workflow.extractionRules)
                }

                // Preview Section
                Section("Preview") {
                    HStack {
                        TextField("Test filename", text: $previewFilename)
                            .textFieldStyle(.roundedBorder)

                        Button("Test") {
                            showingPreview = true
                        }
                    }

                    if showingPreview {
                        PreviewResultView(
                            filename: previewFilename,
                            workflow: workflow
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Workflow" : "Edit Workflow")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            try? await onSave(workflow)
                            dismiss()
                        }
                    }
                    .disabled(workflow.name.isEmpty || workflow.bucket.isEmpty)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 700)
    }
}

// MARK: - Path Template Editor

struct PathTemplateEditor: View {
    @Binding var template: PathTemplate

    @State private var pathSegments: [PathSegment] = []
    @State private var showingPlaceholderPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Current template display
            HStack(spacing: 0) {
                Text("s3://bucket/")
                    .foregroundStyle(.secondary)

                Text(template.template)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            .font(.system(.body, design: .monospaced))
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Visual path builder
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(pathSegments.indices, id: \.self) { index in
                        PathSegmentView(
                            segment: pathSegments[index],
                            onRemove: { removeSegment(at: index) }
                        )
                    }

                    // Add button
                    Menu {
                        Button("Add Placeholder") {
                            showingPlaceholderPicker = true
                        }

                        Button("Add Text") {
                            addTextSegment()
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .menuStyle(.borderlessButton)
                }
                .padding(.vertical, 8)
            }

            // Quick placeholders
            Text("Quick Add:")
                .font(.caption)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(CommonPlaceholder.allCases, id: \.rawValue) { placeholder in
                    Button {
                        addPlaceholder(placeholder.rawValue)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: placeholder.icon)
                            Text(placeholder.rawValue)
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Raw template editor
            DisclosureGroup("Advanced: Raw Template") {
                TextField("Path template", text: $template.template)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: template.template) { _, newValue in
                        parseTemplate()
                    }
            }
        }
        .onAppear {
            parseTemplate()
        }
        .sheet(isPresented: $showingPlaceholderPicker) {
            PlaceholderPickerView { placeholder in
                addPlaceholder(placeholder)
            }
        }
    }

    private func parseTemplate() {
        // Parse template string into segments
        var segments: [PathSegment] = []
        var current = ""
        var inPlaceholder = false

        for char in template.template {
            if char == "{" {
                if !current.isEmpty {
                    segments.append(.text(current))
                    current = ""
                }
                inPlaceholder = true
            } else if char == "}" && inPlaceholder {
                segments.append(.placeholder(current))
                current = ""
                inPlaceholder = false
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            segments.append(.text(current))
        }

        pathSegments = segments
    }

    private func updateTemplate() {
        template.template = pathSegments.map { segment in
            switch segment {
            case .text(let text):
                return text
            case .placeholder(let name):
                return "{\(name)}"
            }
        }.joined()
    }

    private func addPlaceholder(_ name: String) {
        pathSegments.append(.placeholder(name))
        updateTemplate()
    }

    private func addTextSegment() {
        pathSegments.append(.text("/"))
        updateTemplate()
    }

    private func removeSegment(at index: Int) {
        pathSegments.remove(at: index)
        updateTemplate()
    }
}

// MARK: - Path Segment

enum PathSegment {
    case text(String)
    case placeholder(String)
}

struct PathSegmentView: View {
    let segment: PathSegment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            switch segment {
            case .text(let text):
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

            case .placeholder(let name):
                HStack(spacing: 4) {
                    Image(systemName: "tag.fill")
                        .font(.caption2)
                    Text(name)
                        .font(.system(.caption, design: .monospaced))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Common Placeholders

enum CommonPlaceholder: String, CaseIterable {
    case show = "show"
    case episode = "episode"
    case shot = "shot"
    case sequence = "sequence"
    case category = "category"
    case version = "version"
    case date = "date"
    case artist = "artist"

    var icon: String {
        switch self {
        case .show: return "film"
        case .episode: return "number"
        case .shot: return "viewfinder"
        case .sequence: return "photo.on.rectangle"
        case .category: return "folder"
        case .version: return "arrow.triangle.branch"
        case .date: return "calendar"
        case .artist: return "person"
        }
    }
}

// MARK: - Placeholder Picker View

struct PlaceholderPickerView: View {
    @Environment(\.dismiss) var dismiss
    @State private var customName = ""

    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Common Placeholders") {
                    ForEach(CommonPlaceholder.allCases, id: \.rawValue) { placeholder in
                        Button {
                            onSelect(placeholder.rawValue)
                            dismiss()
                        } label: {
                            Label(placeholder.rawValue, systemImage: placeholder.icon)
                        }
                    }
                }

                Section("Custom Placeholder") {
                    HStack {
                        TextField("Custom name", text: $customName)

                        Button("Add") {
                            if !customName.isEmpty {
                                onSelect(customName)
                                dismiss()
                            }
                        }
                        .disabled(customName.isEmpty)
                    }
                }
            }
            .navigationTitle("Add Placeholder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 350, height: 400)
    }
}

// MARK: - Extraction Rules Editor

struct ExtractionRulesEditor: View {
    @Binding var rules: [ExtractionRule]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rules.indices, id: \.self) { index in
                ExtractionRuleRow(
                    rule: $rules[index],
                    onRemove: { rules.remove(at: index) }
                )
            }

            Button {
                rules.append(ExtractionRule(
                    name: "New Rule",
                    pattern: ".*",
                    captureGroupMappings: []
                ))
            } label: {
                Label("Add Extraction Rule", systemImage: "plus.circle")
            }
        }
    }
}

struct ExtractionRuleRow: View {
    @Binding var rule: ExtractionRule
    let onRemove: () -> Void

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Rule Name", text: $rule.name)

                TextField("Regex Pattern", text: $rule.pattern)
                    .font(.system(.body, design: .monospaced))

                Toggle("Enabled", isOn: $rule.enabled)

                // Group mappings
                Text("Capture Group Mappings:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(rule.captureGroupMappings) { mapping in
                    HStack {
                        Text(mapping.placeholderName)
                        Spacer()
                        Text("Group \(mapping.groupIndex)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .padding(.vertical, 8)
        } label: {
            HStack {
                Image(systemName: rule.enabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(rule.enabled ? .green : .secondary)

                Text(rule.name)
                    .fontWeight(.medium)

                Spacer()

                Button {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Preview Result View

struct PreviewResultView: View {
    let filename: String
    let workflow: WorkflowConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Extracted values
            let extracted = extractValues()

            if extracted.isEmpty {
                Text("No values extracted")
                    .foregroundStyle(.secondary)
            } else {
                Text("Extracted Values:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(extracted.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(key)
                            .fontWeight(.medium)
                        Spacer()
                        Text(extracted[key] ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }

            Divider()

            // Resulting path
            Text("Destination Path:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(buildPath(with: extracted))
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func extractValues() -> [String: String] {
        var values: [String: String] = [:]

        for rule in workflow.extractionRules where rule.enabled {
            if let regex = try? NSRegularExpression(pattern: rule.pattern, options: []),
               let match = regex.firstMatch(
                in: filename,
                options: [],
                range: NSRange(filename.startIndex..., in: filename)
               ) {
                for mapping in rule.captureGroupMappings {
                    if mapping.groupIndex < match.numberOfRanges,
                       let range = Range(match.range(at: mapping.groupIndex), in: filename) {
                        values[mapping.placeholderName] = String(filename[range])
                    }
                }
            }
        }

        return values
    }

    private func buildPath(with values: [String: String]) -> String {
        return workflow.pathTemplate.buildPath(with: values)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, proposal: proposal).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let offsets = layout(sizes: sizes, proposal: proposal).offsets

        for (offset, subview) in zip(offsets, subviews) {
            subview.place(
                at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(sizes: [CGSize], proposal: ProposedViewSize) -> (offsets: [CGPoint], size: CGSize) {
        let width = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for size in sizes {
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxWidth = max(maxWidth, currentX)
        }

        return (offsets, CGSize(width: maxWidth, height: currentY + lineHeight))
    }
}

// Note: AWSRegion is now defined in ShotDropperCore.AWSRegion with all S3 regions

// MARK: - Preview

#Preview {
    VisualWorkflowEditorView { workflow in
        print("Saved: \(workflow)")
    }
    .environmentObject(AppState())
}
