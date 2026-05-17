import Foundation

enum DefaultConfig {
    static let contents = """
    {
      "terminal": "iterm",
      "open": "tab",
      "items": [
        {
          "title": "Example SSH",
          "command": "ssh user@example.com"
        },
        {
          "title": "Example Docs",
          "url": "https://example.com"
        },
        {
          "title": "Local",
          "items": [
            {
              "title": "System Log",
              "command": "tail -f /var/log/system.log",
              "open": "window"
            }
          ]
        }
      ]
    }
    """
}
