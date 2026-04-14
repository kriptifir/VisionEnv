import Foundation
import SwiftUI
import UIKit

@MainActor
final class EnvironmentGenerator: ObservableObject {
    enum GenerationError: LocalizedError {
        case invalidPrompt
        case invalidResponse
        case imageDecodingFailed
        case immersiveSpaceUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidPrompt:
                return "Enter a prompt before generating an environment."
            case .invalidResponse:
                return "The image service returned an unexpected response."
            case .imageDecodingFailed:
                return "The generated image could not be decoded."
            case .immersiveSpaceUnavailable:
                return "The immersive space could not be opened."
            }
        }
    }

    struct OpenAIImagesResponse: Decodable {
        struct ImageData: Decodable {
            let revisedPrompt: String?
            let b64JSON: String?

            enum CodingKeys: String, CodingKey {
                case revisedPrompt = "revised_prompt"
                case b64JSON = "b64_json"
            }
        }

        let data: [ImageData]
    }

    @Published var isLoading = false
    @Published var previewImage: UIImage?
    @Published var currentItem: PromptHistory.Item?
    @Published var errorMessage: String?

    private let session: URLSession
    private let fileManager: FileManager
    private let imageDirectory: URL

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager

        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = baseURL.appendingPathComponent("VisionEnv", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        self.imageDirectory = directory
    }

    func generateEnvironment(from prompt: String) async throws -> PromptHistory.Item {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw GenerationError.invalidPrompt
        }

        isLoading = true
        defer { isLoading = false }

        let imageData = try await requestImageData(for: trimmedPrompt)
        let savedURL = try saveImageData(imageData, prompt: trimmedPrompt)
        let image = try loadImage(from: savedURL)

        let item = PromptHistory.Item(
            prompt: trimmedPrompt,
            localImagePath: savedURL.path,
            createdAt: .now
        )

        previewImage = image
        currentItem = item
        return item
    }

    func loadHistoryItem(_ item: PromptHistory.Item) async throws {
        let fileURL = URL(fileURLWithPath: item.localImagePath)
        let image = try loadImage(from: fileURL)
        previewImage = image
        currentItem = item
        errorMessage = nil
    }

    func imageFileURLForCurrentItem() -> URL? {
        guard let path = currentItem?.localImagePath else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func requestImageData(for prompt: String) async throws -> Data {
        if let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty {
            return try await generateWithOpenAI(prompt: prompt, apiKey: apiKey)
        }

        return try await generatePlaceholder(prompt: prompt)
    }

    private func generateWithOpenAI(prompt: String, apiKey: String) async throws -> Data {
        let url = URL(string: "https://api.openai.com/v1/images/generations")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let requestBody: [String: Any] = [
            "model": "dall-e-3",
            "prompt": """
            Create a high-quality equirectangular 360 panorama environment for Apple Vision Pro. \
            The scene should fully surround the viewer with coherent horizon lines and immersive detail. \
            Style request: nanobanana-pro-quality. Scene prompt: \(prompt)
            """,
            "size": "1792x1024",
            "quality": "hd",
            "response_format": "b64_json"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GenerationError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let serverMessage = String(data: data, encoding: .utf8) ?? "Image generation failed."
            throw NSError(
                domain: "OpenAIImageGeneration",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: serverMessage]
            )
        }

        let decoded = try JSONDecoder().decode(OpenAIImagesResponse.self, from: data)
        guard let first = decoded.data.first, let base64 = first.b64JSON, let imageData = Data(base64Encoded: base64) else {
            throw GenerationError.invalidResponse
        }

        return imageData
    }

    private func generatePlaceholder(prompt: String) async throws -> Data {
        let escapedPrompt = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "vision"
        let seed = abs(prompt.hashValue)
        let url = URL(string: "https://picsum.photos/seed/\(seed)/1792/1024?blur=1&grayscale=0&tag=\(escapedPrompt)")!
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw GenerationError.invalidResponse
        }
        return data
    }

    private func saveImageData(_ data: Data, prompt: String) throws -> URL {
        let filename = sanitizedFilename(from: prompt) + "-" + UUID().uuidString + ".png"
        let fileURL = imageDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func loadImage(from fileURL: URL) throws -> UIImage {
        let data = try Data(contentsOf: fileURL)
        guard let image = UIImage(data: data) else {
            throw GenerationError.imageDecodingFailed
        }
        return image
    }

    private func sanitizedFilename(from prompt: String) -> String {
        let raw = prompt.lowercased().replacingOccurrences(of: " ", with: "-")
        let allowed = raw.unicodeScalars.filter {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0)
        }
        return String(String.UnicodeScalarView(allowed)).prefix(32).description
    }
}
