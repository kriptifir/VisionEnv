import Foundation

@MainActor
final class PromptHistory: ObservableObject {
    struct Item: Codable, Identifiable, Hashable {
        let id: UUID
        let prompt: String
        let localImagePath: String
        let createdAt: Date

        init(id: UUID = UUID(), prompt: String, localImagePath: String, createdAt: Date) {
            self.id = id
            self.prompt = prompt
            self.localImagePath = localImagePath
            self.createdAt = createdAt
        }
    }

    @Published private(set) var items: [Item] = []

    private let userDefaults: UserDefaults
    private let storageKey = "visionenv.prompt-history"
    private let maxItems = 5

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        load()
    }

    func load() {
        guard let data = userDefaults.data(forKey: storageKey) else {
            items = []
            return
        }

        do {
            items = try JSONDecoder().decode([Item].self, from: data)
        } catch {
            items = []
        }
    }

    func add(_ item: Item) {
        var updated = items.filter { $0.localImagePath != item.localImagePath }
        updated.insert(item, at: 0)
        items = Array(updated.prefix(maxItems))
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(items)
            userDefaults.set(data, forKey: storageKey)
        } catch {
            assertionFailure("Failed to persist prompt history: \(error)")
        }
    }
}
