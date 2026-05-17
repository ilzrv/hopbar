import Foundation

enum ConfigStoreError: Error, Equatable, CustomStringConvertible {
    case defaultWriteFailed(String)
    case readFailed(String)
    case invalidJSON(String)
    case validation(String)
    case metadataUnavailable(String)

    var description: String {
        switch self {
        case .defaultWriteFailed(let message):
            return "Could not create default config: \(message)"
        case .readFailed(let message):
            return "Could not read config: \(message)"
        case .invalidJSON(let message):
            return "Invalid JSON: \(message)"
        case .validation(let message):
            return "Invalid config: \(message)"
        case .metadataUnavailable(let message):
            return "Could not read config metadata: \(message)"
        }
    }
}

struct ConfigStore {
    let configURL: URL
    private let defaultConfigContents: String
    private let fileManager: FileManager

    init(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hopbar.json"),
        defaultConfigContents: String = DefaultConfig.contents,
        fileManager: FileManager = .default
    ) {
        self.configURL = configURL
        self.defaultConfigContents = defaultConfigContents
        self.fileManager = fileManager
    }

    func ensureConfigExists() -> Result<Void, ConfigStoreError> {
        guard !fileManager.fileExists(atPath: configURL.path) else {
            return .success(())
        }

        do {
            let directory = configURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try defaultConfigContents.write(to: configURL, atomically: true, encoding: .utf8)
            return .success(())
        } catch {
            return .failure(.defaultWriteFailed(error.localizedDescription))
        }
    }

    func load() -> Result<MenuModel, ConfigStoreError> {
        do {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            let config = try decoder.decode(HopbarConfig.self, from: data)
            return .success(try MenuModelBuilder.build(from: config))
        } catch let error as DecodingError {
            return .failure(.invalidJSON(Self.describe(error)))
        } catch let error as ConfigValidationError {
            return .failure(.validation(error.description))
        } catch {
            return .failure(.readFailed(error.localizedDescription))
        }
    }

    func modificationDate() -> Result<Date?, ConfigStoreError> {
        guard fileManager.fileExists(atPath: configURL.path) else {
            return .success(nil)
        }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: configURL.path)
            return .success(attributes[.modificationDate] as? Date)
        } catch {
            return .failure(.metadataUnavailable(error.localizedDescription))
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context):
            return context.debugDescription
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(context.codingPath.pathDescription)."
        case .typeMismatch(_, let context):
            return "Type mismatch at \(context.codingPath.pathDescription): \(context.debugDescription)"
        case .valueNotFound(_, let context):
            return "Missing value at \(context.codingPath.pathDescription): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}

private extension Array where Element == CodingKey {
    var pathDescription: String {
        guard !isEmpty else {
            return "root"
        }
        return map(\.stringValue).joined(separator: ".")
    }
}
