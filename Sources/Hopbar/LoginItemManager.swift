import Foundation
import ServiceManagement

enum LoginItemError: Error, CustomStringConvertible {
    case unsupported

    var description: String {
        switch self {
        case .unsupported:
            return "Launch at login requires macOS 13 or newer."
        }
    }
}

struct LoginItemManager {
    var isSupported: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    var isEnabled: Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }
        return SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw LoginItemError.unsupported
        }

        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
