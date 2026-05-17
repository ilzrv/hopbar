import Foundation

enum TerminalPreference: String, CaseIterable, Equatable {
    case iterm
    case terminal
}

extension TerminalPreference: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let value = TerminalPreference(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid terminal '\(rawValue)'. Expected one of: iterm, terminal."
            )
        }
        self = value
    }
}

enum OpenMode: String, CaseIterable, Equatable {
    case tab
    case window
    case current
}

extension OpenMode: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let value = OpenMode(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid open mode '\(rawValue)'. Expected one of: tab, window, current."
            )
        }
        self = value
    }
}

struct MenuModel: Equatable {
    let entries: [MenuEntry]
}

struct MenuEntry: Equatable {
    let title: String
    let kind: Kind

    enum Kind: Equatable {
        case command(String, terminal: TerminalPreference, open: OpenMode)
        case url(URL)
        case group([MenuEntry])
    }
}

struct HopbarConfig: Decodable {
    let terminal: TerminalPreference?
    let open: OpenMode?
    let items: [RawMenuItem]
}

struct RawMenuItem: Decodable {
    let title: String
    let command: String?
    let url: String?
    let items: [RawMenuItem]?
    let terminal: TerminalPreference?
    let open: OpenMode?
}

enum ConfigValidationError: Error, Equatable, CustomStringConvertible {
    case emptyTitle(path: String)
    case duplicateTitle(title: String, path: String)
    case invalidLeafShape(title: String, path: String)
    case emptyCommand(title: String, path: String)
    case invalidURL(title: String, value: String, path: String)
    case emptyGroup(title: String, path: String)

    var description: String {
        switch self {
        case .emptyTitle(let path):
            return "Menu item at \(path) has an empty title."
        case .duplicateTitle(let title, let path):
            return "Duplicate menu title '\(title)' at \(path)."
        case .invalidLeafShape(let title, let path):
            return "Menu item '\(title)' at \(path) must define exactly one of command, url, or items."
        case .emptyCommand(let title, let path):
            return "Menu item '\(title)' at \(path) has an empty command."
        case .invalidURL(let title, let value, let path):
            return "Menu item '\(title)' at \(path) has an invalid URL '\(value)'."
        case .emptyGroup(let title, let path):
            return "Menu group '\(title)' at \(path) must contain at least one item."
        }
    }
}

enum MenuModelBuilder {
    static func build(from config: HopbarConfig) throws -> MenuModel {
        let terminal = config.terminal ?? .iterm
        let open = config.open ?? .tab
        return MenuModel(entries: try buildEntries(
            from: config.items,
            inheritedTerminal: terminal,
            inheritedOpen: open,
            path: "items"
        ))
    }

    private static func buildEntries(
        from rawItems: [RawMenuItem],
        inheritedTerminal: TerminalPreference,
        inheritedOpen: OpenMode,
        path: String
    ) throws -> [MenuEntry] {
        var seenTitles = Set<String>()
        var entries: [MenuEntry] = []

        for (index, item) in rawItems.enumerated() {
            let itemPath = "\(path)[\(index)]"
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !title.isEmpty else {
                throw ConfigValidationError.emptyTitle(path: itemPath)
            }

            let normalizedTitle = title.lowercased()
            guard seenTitles.insert(normalizedTitle).inserted else {
                throw ConfigValidationError.duplicateTitle(title: title, path: path)
            }

            let hasCommand = item.command != nil
            let hasURL = item.url != nil
            let hasItems = item.items != nil
            guard [hasCommand, hasURL, hasItems].filter({ $0 }).count == 1 else {
                throw ConfigValidationError.invalidLeafShape(title: title, path: itemPath)
            }

            let terminal = item.terminal ?? inheritedTerminal
            let open = item.open ?? inheritedOpen

            if let command = item.command {
                let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedCommand.isEmpty else {
                    throw ConfigValidationError.emptyCommand(title: title, path: itemPath)
                }
                entries.append(MenuEntry(title: title, kind: .command(trimmedCommand, terminal: terminal, open: open)))
                continue
            }

            if let urlString = item.url {
                let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: trimmedURL), url.scheme != nil else {
                    throw ConfigValidationError.invalidURL(title: title, value: urlString, path: itemPath)
                }
                entries.append(MenuEntry(title: title, kind: .url(url)))
                continue
            }

            if let childItems = item.items {
                guard !childItems.isEmpty else {
                    throw ConfigValidationError.emptyGroup(title: title, path: itemPath)
                }
                let children = try buildEntries(
                    from: childItems,
                    inheritedTerminal: terminal,
                    inheritedOpen: open,
                    path: "\(itemPath).items"
                )
                entries.append(MenuEntry(title: title, kind: .group(children)))
            }
        }

        return entries
    }
}
