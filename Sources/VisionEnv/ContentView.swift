import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var generator: EnvironmentGenerator
    @EnvironmentObject private var promptHistory: PromptHistory
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var prompt = "tropical beach at sunset"
    @State private var immersiveSpaceIsOpen = false
    @FocusState private var promptFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                header
                promptComposer
                previewCard
                historySection
                Spacer()
            }
            .padding(24)
            .navigationTitle("VisionEnv")
        }
        .frame(minWidth: 720, minHeight: 900)
        .task {
            if promptHistory.items.isEmpty {
                promptHistory.load()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI immersive environments")
                .font(.largeTitle.weight(.bold))
            Text("Generate a panoramic scene from a prompt and wrap it around the user in an immersive space.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var promptComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prompt")
                .font(.headline)

            TextField("Describe the environment", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($promptFieldFocused)
                .lineLimit(2...4)

            HStack(spacing: 12) {
                Button {
                    Task {
                        await generateEnvironment()
                    }
                } label: {
                    if generator.isLoading {
                        Label("Generating…", systemImage: "hourglass")
                    } else {
                        Label("Generate", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(generator.isLoading || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Use Latest Prompt") {
                    if let latest = promptHistory.items.first {
                        prompt = latest.prompt
                    }
                }
                .buttonStyle(.bordered)
                .disabled(promptHistory.items.isEmpty)

                if immersiveSpaceIsOpen {
                    Button("Close 360 View") {
                        Task {
                            await dismissImmersiveSpace()
                            immersiveSpaceIsOpen = false
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let errorMessage = generator.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latest Environment")
                .font(.headline)

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))

                if let image = generator.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(12)
                } else {
                    ContentUnavailableView(
                        "No environment yet",
                        systemImage: "globe.americas",
                        description: Text("Generate a scene to preview it here and in the immersive space.")
                    )
                }

                if generator.isLoading {
                    ProgressView("Creating panoramic texture")
                        .padding()
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .frame(height: 320)

            if let currentPrompt = generator.currentItem?.prompt {
                Text(currentPrompt)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Generations")
                .font(.headline)

            if promptHistory.items.isEmpty {
                Text("Your last five generated environments will appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(promptHistory.items) { item in
                            Button {
                                Task {
                                    await loadHistoryItem(item)
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    historyThumbnail(for: item)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.prompt)
                                            .font(.body.weight(.medium))
                                            .multilineTextAlignment(.leading)
                                            .foregroundStyle(.primary)
                                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.clockwise.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func historyThumbnail(for item: PromptHistory.Item) -> some View {
        if let image = UIImage(contentsOfFile: item.localImagePath) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 64)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 96, height: 64)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func generateEnvironment() async {
        promptFieldFocused = false
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let item = try await generator.generateEnvironment(from: trimmedPrompt)
            promptHistory.add(item)
            try await presentImmersiveSpaceIfNeeded()
            generator.errorMessage = nil
        } catch {
            generator.errorMessage = error.localizedDescription
        }
    }

    private func loadHistoryItem(_ item: PromptHistory.Item) async {
        do {
            try await generator.loadHistoryItem(item)
            prompt = item.prompt
            try await presentImmersiveSpaceIfNeeded()
        } catch {
            generator.errorMessage = error.localizedDescription
        }
    }

    private func presentImmersiveSpaceIfNeeded() async throws {
        if immersiveSpaceIsOpen {
            return
        }

        let result = await openImmersiveSpace(id: PanoramaView.immersiveSpaceID)
        switch result {
        case .opened:
            immersiveSpaceIsOpen = true
        case .error, .userCancelled:
            throw EnvironmentGenerator.GenerationError.immersiveSpaceUnavailable
        @unknown default:
            throw EnvironmentGenerator.GenerationError.immersiveSpaceUnavailable
        }
    }
}
