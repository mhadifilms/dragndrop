import SwiftUI
import ShotDropperCore

// MARK: - Region Selector View

/// A comprehensive region selector with latency testing
struct RegionSelectorView: View {
    @Binding var selectedRegionId: String
    @State private var results: [RegionLatencyResult] = []
    @State private var isTestingLatency = false
    @State private var showAllRegions = false
    @State private var searchText = ""
    @State private var hasAppeared = false

    private let latencyService = AWSRegionLatencyService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection

            if !results.isEmpty {
                resultsSection
            }

            regionListSection

            footerSection
        }
        .task {
            await setupLatencyService()
            // Auto-test common regions on appear
            if results.isEmpty {
                await testCommonRegions()
            }
            withAnimation(AnimationPresets.spring) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AWS Region")
                    .font(.headline)

                Spacer()

                Button {
                    Task {
                        await testAllRegions()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isTestingLatency {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text(isTestingLatency ? "Testing..." : "Test Latency")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(isTestingLatency)
            }

            Text("Select the closest region for best upload performance")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latency Results")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(results.prefix(6)) { result in
                    LatencyResultCard(
                        result: result,
                        isSelected: result.region.id == selectedRegionId
                    ) {
                        withAnimation(AnimationPresets.snappy) {
                            selectedRegionId = result.region.id
                        }
                    }
                }
            }

            if let bestRegion = results.first(where: { $0.latencyMs != nil }) {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("Recommended: ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(bestRegion.region.flag) \(bestRegion.region.name)")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("(\(Int(bestRegion.latencyMs ?? 0)) ms)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if selectedRegionId != bestRegion.region.id {
                        Button("Use") {
                            withAnimation(AnimationPresets.snappy) {
                                selectedRegionId = bestRegion.region.id
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(8)
                .background(.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 10)
    }

    // MARK: - Region List Section

    private var regionListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("All Regions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("Show All", isOn: $showAllRegions)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            TextField("Search regions...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(AWSRegion.Continent.allCases, id: \.rawValue) { continent in
                        let regionsForContinent = filteredRegions(for: continent)
                        if !regionsForContinent.isEmpty {
                            ContinentSection(
                                continent: continent,
                                regions: regionsForContinent,
                                selectedRegionId: $selectedRegionId,
                                results: results
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: showAllRegions ? 300 : 150)
        }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack {
            if let selectedRegion = AWSRegion.region(for: selectedRegionId) {
                HStack(spacing: 8) {
                    Text(selectedRegion.flag)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected Region")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selectedRegion.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }

            Spacer()

            if let result = results.first(where: { $0.region.id == selectedRegionId }),
               let latency = result.latencyMs {
                LatencyBadge(latencyMs: latency)
            }
        }
        .padding()
        .background(.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Methods

    private func filteredRegions(for continent: AWSRegion.Continent) -> [AWSRegion] {
        let continentRegions = AWSRegion.regionsByContinent[continent] ?? []

        if searchText.isEmpty {
            return showAllRegions ? continentRegions : continentRegions.filter { AWSRegion.commonRegions.contains($0) }
        }

        return continentRegions.filter { region in
            region.name.localizedCaseInsensitiveContains(searchText) ||
            region.id.localizedCaseInsensitiveContains(searchText) ||
            region.city.localizedCaseInsensitiveContains(searchText)
        }
    }

    @MainActor
    private func setupLatencyService() async {
        await latencyService.setUpdateCallback { newResults in
            Task { @MainActor in
                self.results = newResults
            }
        }
    }

    @MainActor
    private func testCommonRegions() async {
        isTestingLatency = true
        _ = await latencyService.testCommonRegions()
        isTestingLatency = false
    }

    @MainActor
    private func testAllRegions() async {
        isTestingLatency = true
        showAllRegions = true
        _ = await latencyService.testAllRegions()
        isTestingLatency = false
    }
}

// MARK: - Latency Result Card

struct LatencyResultCard: View {
    let result: RegionLatencyResult
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(result.region.flag)
                        .font(.title3)
                    Spacer()
                    latencyIndicator
                }

                Text(result.region.city)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(result.latencyDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(AnimationPresets.snappy, value: isHovered)
    }

    @ViewBuilder
    private var latencyIndicator: some View {
        switch result.status {
        case .testing:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
        case .success:
            Circle()
                .fill(qualityColor)
                .frame(width: 8, height: 8)
        case .failed, .timeout:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    private var qualityColor: Color {
        switch result.qualityRating {
        case .excellent, .good: return .green
        case .fair: return .yellow
        case .poor: return .orange
        case .bad: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Continent Section

struct ContinentSection: View {
    let continent: AWSRegion.Continent
    let regions: [AWSRegion]
    @Binding var selectedRegionId: String
    let results: [RegionLatencyResult]

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(AnimationPresets.snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text(continent.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(regions.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color.secondary.opacity(0.05))
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(regions) { region in
                    RegionRow(
                        region: region,
                        isSelected: region.id == selectedRegionId,
                        latencyResult: results.first { $0.region.id == region.id }
                    ) {
                        withAnimation(AnimationPresets.snappy) {
                            selectedRegionId = region.id
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Region Row

struct RegionRow: View {
    let region: AWSRegion
    let isSelected: Bool
    let latencyResult: RegionLatencyResult?
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Text(region.flag)
                    .font(.body)

                VStack(alignment: .leading, spacing: 1) {
                    Text(region.name)
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? .primary : .primary)

                    Text(region.id)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let result = latencyResult {
                    LatencyBadge(result: result)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Latency Badge

struct LatencyBadge: View {
    let latencyMs: Double?
    let status: RegionLatencyResult.Status?

    init(latencyMs: Double) {
        self.latencyMs = latencyMs
        self.status = .success
    }

    init(result: RegionLatencyResult) {
        self.latencyMs = result.latencyMs
        self.status = result.status
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(qualityColor)
                .frame(width: 6, height: 6)

            switch status {
            case .testing:
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            case .success:
                if let ms = latencyMs {
                    Text("\(Int(ms)) ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .failed, .timeout:
                Text("N/A")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(qualityColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var qualityColor: Color {
        guard let ms = latencyMs else { return .gray }
        switch ms {
        case ..<50: return .green
        case 50..<100: return .green.opacity(0.8)
        case 100..<200: return .yellow
        case 200..<500: return .orange
        default: return .red
        }
    }
}

// MARK: - Compact Region Selector

/// A compact region selector for use in forms
struct CompactRegionSelector: View {
    @Binding var selectedRegionId: String
    @State private var showingPicker = false

    var body: some View {
        HStack {
            if let region = AWSRegion.region(for: selectedRegionId) {
                HStack(spacing: 8) {
                    Text(region.flag)
                    Text(region.name)
                        .lineLimit(1)
                }
            } else {
                Text("Select Region")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showingPicker = true
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $showingPicker) {
            RegionPickerSheet(selectedRegionId: $selectedRegionId)
        }
    }
}

// MARK: - Region Picker Sheet

struct RegionPickerSheet: View {
    @Binding var selectedRegionId: String
    @Environment(\.dismiss) private var dismiss
    @State private var tempSelection: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select AWS Region")
                    .font(.headline)

                Spacer()

                Button("Done") {
                    selectedRegionId = tempSelection
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            RegionSelectorView(selectedRegionId: $tempSelection)
                .padding()
        }
        .frame(width: 500, height: 600)
        .onAppear {
            tempSelection = selectedRegionId
        }
    }
}

// MARK: - Preview

#Preview {
    RegionSelectorView(selectedRegionId: .constant("us-east-1"))
        .frame(width: 450)
        .padding()
}
