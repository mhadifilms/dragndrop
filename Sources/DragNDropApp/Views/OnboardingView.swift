import SwiftUI
import DragNDropCore

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var currentStep = 0
    @State private var hasAnimatedIn = false

    private let totalSteps = 4

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.1),
                    Color.purple.opacity(0.05),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress indicator
                OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)

                // Content - using ZStack for macOS compatibility
                ZStack {
                    WelcomeStep()
                        .opacity(currentStep == 0 ? 1 : 0)
                        .offset(x: currentStep == 0 ? 0 : (currentStep > 0 ? -50 : 50))

                    FeaturesStep()
                        .opacity(currentStep == 1 ? 1 : 0)
                        .offset(x: currentStep == 1 ? 0 : (currentStep > 1 ? -50 : 50))

                    AuthenticationStep()
                        .environmentObject(appState)
                        .opacity(currentStep == 2 ? 1 : 0)
                        .offset(x: currentStep == 2 ? 0 : (currentStep > 2 ? -50 : 50))

                    WorkflowStep()
                        .environmentObject(appState)
                        .opacity(currentStep == 3 ? 1 : 0)
                        .offset(x: currentStep == 3 ? 0 : 50)
                }
                .animation(AnimationPresets.spring, value: currentStep)

                // Navigation buttons
                OnboardingNavigation(
                    currentStep: $currentStep,
                    totalSteps: totalSteps,
                    canProceed: canProceedFromStep,
                    onComplete: completeOnboarding
                )
                .padding(24)
            }
        }
        .frame(width: 600, height: 500)
        .opacity(hasAnimatedIn ? 1 : 0)
        .scaleEffect(hasAnimatedIn ? 1 : 0.9)
        .onAppear {
            withAnimation(AnimationPresets.spring.delay(0.1)) {
                hasAnimatedIn = true
            }
        }
    }

    private var canProceedFromStep: Bool {
        switch currentStep {
        case 0, 1: return true
        case 2: return appState.isAuthenticated
        case 3: return appState.activeWorkflow != nil
        default: return true
        }
    }

    private func completeOnboarding() {
        appState.settings.hasCompletedOnboarding = true
        appState.settings.save()
        dismiss()
    }
}

// MARK: - Progress Bar

struct OnboardingProgressBar: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(height: 4)
                    .animation(AnimationPresets.spring, value: currentStep)
            }
        }
    }
}

// MARK: - Navigation Buttons

struct OnboardingNavigation: View {
    @Binding var currentStep: Int
    let totalSteps: Int
    let canProceed: Bool
    let onComplete: () -> Void

    var body: some View {
        HStack {
            // Back button
            if currentStep > 0 {
                Button {
                    withAnimation(AnimationPresets.spring) {
                        currentStep -= 1
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Skip button (for non-essential steps)
            if currentStep < 2 {
                Button("Skip") {
                    withAnimation(AnimationPresets.spring) {
                        currentStep = 2
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // Next/Complete button
            if currentStep < totalSteps - 1 {
                Button {
                    withAnimation(AnimationPresets.spring) {
                        currentStep += 1
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed)
            } else {
                Button("Get Started") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed)
            }
        }
    }
}

// MARK: - Welcome Step

struct WelcomeStep: View {
    @State private var hasAnimated = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo/Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.accentColor, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: .accentColor.opacity(0.3), radius: 20)

                Image(systemName: "tray.and.arrow.up.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
            }
            .scaleEffect(hasAnimated ? 1 : 0.5)
            .opacity(hasAnimated ? 1 : 0)

            VStack(spacing: 16) {
                Text("Welcome to dragndrop")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .animatedAppearance(delay: 0.2)

                Text("The fastest way to upload VFX files to S3")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .animatedAppearance(delay: 0.3)
            }

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "bolt.fill", text: "Drag and drop to upload")
                FeatureRow(icon: "folder.fill.badge.gearshape", text: "Smart folder organization")
                FeatureRow(icon: "arrow.triangle.2.circlepath", text: "Resume interrupted uploads")
                FeatureRow(icon: "link", text: "Generate shareable links")
            }
            .padding(.top, 16)

            Spacer()
        }
        .padding(32)
        .onAppear {
            withAnimation(AnimationPresets.bouncy) {
                hasAnimated = true
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            Text(text)
                .font(.body)
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(x: hasAppeared ? 0 : -20)
        .onAppear {
            withAnimation(AnimationPresets.spring.delay(0.4)) {
                hasAppeared = true
            }
        }
    }
}

// MARK: - Features Step

struct FeaturesStep: View {
    @State private var selectedFeature = 0

    let features = [
        OnboardingFeature(
            icon: "wand.and.rays",
            title: "VFX-Optimized",
            description: "Built specifically for Nuke comps (.nk), EXR sequences, ProRes videos, and other VFX file formats.",
            color: .orange
        ),
        OnboardingFeature(
            icon: "text.magnifyingglass",
            title: "Smart Path Extraction",
            description: "Automatically extracts show, episode, and shot info from filenames to organize your uploads.",
            color: .purple
        ),
        OnboardingFeature(
            icon: "speedometer",
            title: "High Performance",
            description: "Multipart uploads with bandwidth control and automatic retry for reliable transfers.",
            color: .blue
        ),
        OnboardingFeature(
            icon: "arrow.triangle.branch",
            title: "Workflow Templates",
            description: "Create reusable workflows for different projects with custom folder structures.",
            color: .green
        )
    ]

    var body: some View {
        VStack(spacing: 24) {
            Text("Powerful Features")
                .font(.title)
                .fontWeight(.bold)
                .animatedAppearance(delay: 0)

            // Feature cards
            HStack(spacing: 16) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    FeatureCard(
                        feature: feature,
                        isSelected: selectedFeature == index,
                        delay: Double(index) * 0.1
                    )
                    .onTapGesture {
                        withAnimation(AnimationPresets.spring) {
                            selectedFeature = index
                        }
                    }
                }
            }
            .padding(.horizontal, 24)

            // Selected feature detail
            VStack(spacing: 12) {
                Text(features[selectedFeature].title)
                    .font(.headline)
                    .id(selectedFeature)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                Text(features[selectedFeature].description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                    .id("desc-\(selectedFeature)")
                    .transition(.opacity)
            }
            .animation(AnimationPresets.smooth, value: selectedFeature)
            .padding(.top, 8)
        }
        .padding(32)
    }
}

struct OnboardingFeature {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

struct FeatureCard: View {
    let feature: OnboardingFeature
    let isSelected: Bool
    let delay: Double

    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(feature.color.opacity(isSelected ? 0.2 : 0.1))
                    .frame(width: 60, height: 60)

                Image(systemName: feature.icon)
                    .font(.title2)
                    .foregroundStyle(feature.color)
            }

            Text(feature.title)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? feature.color.opacity(0.1) : Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isSelected ? feature.color.opacity(0.3) : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 20)
        .animation(AnimationPresets.spring, value: isSelected)
        .onAppear {
            withAnimation(AnimationPresets.spring.delay(delay)) {
                hasAppeared = true
            }
        }
    }
}

// MARK: - Authentication Step

struct AuthenticationStep: View {
    @EnvironmentObject var appState: AppState
    @State private var isAuthenticating = false
    @State private var authError: String?
    @State private var accessKey = ""
    @State private var secretKey = ""

    var body: some View {
        VStack(spacing: 32) {
            // Icon
            ZStack {
                if appState.isAuthenticated {
                    AnimatedCheckmark(color: .green)
                        .frame(width: 80, height: 80)
                } else {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)
                }
            }
            .animatedAppearance(delay: 0.1)

            VStack(spacing: 12) {
                Text(appState.isAuthenticated ? "You're Connected!" : "Connect to AWS")
                    .font(.title)
                    .fontWeight(.bold)

                Text(appState.isAuthenticated
                    ? "Your AWS account is ready to use."
                    : "Enter your AWS credentials to start uploading files to S3.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .animatedAppearance(delay: 0.2)

            if !appState.isAuthenticated {
                VStack(spacing: 16) {
                    // Credentials input
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Access Key ID", text: $accessKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                            .font(.system(.body, design: .monospaced))

                        SecureField("Secret Access Key", text: $secretKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                            .font(.system(.body, design: .monospaced))
                    }

                    Button {
                        testCredentials()
                    } label: {
                        HStack(spacing: 8) {
                            if isAuthenticating {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "checkmark.shield")
                            }
                            Text(isAuthenticating ? "Testing..." : "Test Connection")
                        }
                        .frame(minWidth: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(accessKey.isEmpty || secretKey.isEmpty || isAuthenticating)

                    if let error = authError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Text("Get your access keys from AWS Console → IAM → Security credentials")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .animatedAppearance(delay: 0.3)
            } else {
                // Connected state
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Credentials verified!")
                            .font(.subheadline)
                    }

                    Button("Clear credentials") {
                        Task { await appState.signOut() }
                        accessKey = ""
                        secretKey = ""
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .animatedAppearance(delay: 0.3)
            }
        }
        .padding(32)
    }

    private func testCredentials() {
        isAuthenticating = true
        authError = nil

        Task {
            do {
                try await appState.setCredentials(
                    accessKey: accessKey,
                    secretKey: secretKey,
                    region: appState.settings.awsRegion
                )
            } catch {
                authError = error.localizedDescription
            }
            isAuthenticating = false
        }
    }
}

// MARK: - Workflow Step

struct WorkflowStep: View {
    @EnvironmentObject var appState: AppState
    @State private var workflows: [WorkflowConfiguration] = []
    @State private var selectedWorkflowId: UUID?
    @State private var showingNewWorkflow = false
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                if appState.activeWorkflow != nil {
                    AnimatedCheckmark(color: .green)
                        .frame(width: 80, height: 80)
                } else {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 36))
                        .foregroundStyle(.purple)
                }
            }
            .animatedAppearance(delay: 0.1)

            VStack(spacing: 12) {
                Text(appState.activeWorkflow != nil ? "Workflow Selected!" : "Choose a Workflow")
                    .font(.title)
                    .fontWeight(.bold)

                Text(appState.activeWorkflow != nil
                    ? "You're ready to start uploading files."
                    : "Workflows define where and how your files are organized in S3.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .animatedAppearance(delay: 0.2)

            if appState.activeWorkflow == nil {
                VStack(spacing: 16) {
                    if isLoading {
                        ProgressView()
                    } else if workflows.isEmpty {
                        // No workflows - create first one
                        VStack(spacing: 12) {
                            Text("No workflows yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button {
                                createSampleWorkflow()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Create Sample VFX Workflow")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        // Workflow picker
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(workflows) { workflow in
                                    WorkflowCard(
                                        workflow: workflow,
                                        isSelected: selectedWorkflowId == workflow.id
                                    )
                                    .onTapGesture {
                                        withAnimation(AnimationPresets.spring) {
                                            selectedWorkflowId = workflow.id
                                        }
                                    }
                                }

                                // Add new workflow button
                                Button {
                                    showingNewWorkflow = true
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title)
                                            .foregroundStyle(.secondary)
                                        Text("New")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 100, height: 80)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.secondary.opacity(0.1))
                                            .strokeBorder(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5]))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 32)
                        }

                        if let selectedId = selectedWorkflowId,
                           let selected = workflows.first(where: { $0.id == selectedId }) {
                            Button("Use \"\(selected.name)\"") {
                                Task {
                                    await appState.setActiveWorkflow(selected)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .animatedAppearance(delay: 0.3)
            } else {
                // Workflow selected
                if let workflow = appState.activeWorkflow {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(workflow.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        Text("s3://\(workflow.bucket)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Change workflow") {
                            appState.activeWorkflow = nil
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.top, 8)
                    }
                    .animatedAppearance(delay: 0.3)
                }
            }
        }
        .padding(32)
        .task {
            await loadWorkflows()
        }
        .sheet(isPresented: $showingNewWorkflow) {
            WorkflowEditorView(workflow: nil)
                .environmentObject(appState)
        }
    }

    private func loadWorkflows() async {
        isLoading = true
        workflows = await appState.loadWorkflows()
        isLoading = false
    }

    private func createSampleWorkflow() {
        Task {
            let sample = WorkflowConfiguration.sampleVFXWorkflow
            try? await appState.saveWorkflow(sample)
            await loadWorkflows()
            selectedWorkflowId = sample.id
        }
    }
}

struct WorkflowCard: View {
    let workflow: WorkflowConfiguration
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(isSelected ? .white : .purple)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }

            Text(workflow.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(1)

            Text(workflow.bucket)
                .font(.caption)
                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 140, height: 90)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.purple : Color.secondary.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(AnimationPresets.spring, value: isSelected)
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
