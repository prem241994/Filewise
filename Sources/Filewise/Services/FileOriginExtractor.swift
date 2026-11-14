import Foundation

enum FileOriginExtractor {
    /// Extracts the web domain or application origin of a downloaded file
    /// using macOS extended attributes (`com.apple.metadata:kMDItemWhereFroms` and `com.apple.quarantine`).
    static func origin(for url: URL) -> String? {
        let path = url.path

        // 1. Check com.apple.metadata:kMDItemWhereFroms (stores source URL array)
        if let whereFroms = readWhereFroms(path: path) {
            for entry in whereFroms {
                if let parsed = extractDomainName(from: entry) {
                    return parsed
                }
            }
        }

        // 2. Fallback to com.apple.quarantine (stores downloading agent/app name)
        if let quarantine = readXattrString(path: path, name: "com.apple.quarantine") {
            let parts = quarantine.components(separatedBy: ";")
            if parts.count >= 3 {
                let agent = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                if !agent.isEmpty {
                    return cleanAppName(agent)
                }
            }
        }

        return nil
    }

    private static func readWhereFroms(path: String) -> [String]? {
        let xattrName = "com.apple.metadata:kMDItemWhereFroms"
        let size = getxattr(path, xattrName, nil, 0, 0, 0)
        guard size > 0 else { return nil }

        var data = Data(count: size)
        let readSize = data.withUnsafeMutableBytes {
            getxattr(path, xattrName, $0.baseAddress, size, 0, 0)
        }
        guard readSize > 0 else { return nil }

        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let array = plist as? [String] else { return nil }
        return array
    }

    private static func readXattrString(path: String, name: String) -> String? {
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }

        var data = Data(count: size)
        let readSize = data.withUnsafeMutableBytes {
            getxattr(path, name, $0.baseAddress, size, 0, 0)
        }
        guard readSize > 0 else { return nil }

        return String(data: data, encoding: .utf8)
    }

    private static func extractDomainName(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
            return nil
        }

        // Known services clean labels
        if host.contains("canva.com") { return "Canva" }
        if host.contains("chatgpt.com") || host.contains("openai.com") { return "ChatGPT" }
        if host.contains("twitter.com") || host.contains("x.com") { return "X" }
        if host.contains("pinterest.com") || host.contains("pinimg.com") { return "Pinterest" }
        if host.contains("github.com") || host.contains("githubusercontent.com") { return "GitHub" }
        if host.contains("figma.com") { return "Figma" }
        if host.contains("google.com") || host.contains("googleusercontent.com") { return "Google" }
        if host.contains("dropbox.com") { return "Dropbox" }
        if host.contains("slack.com") { return "Slack" }
        if host.contains("notion.so") || host.contains("notion.site") { return "Notion" }
        if host.contains("youtube.com") || host.contains("googlevideo.com") { return "YouTube" }
        if host.contains("gitlab.com") { return "GitLab" }
        if host.contains("stackoverflow.com") { return "Stack Overflow" }
        if host.contains("apple.com") || host.contains("icloud.com") { return "Apple" }
        if host.contains("unsplash.com") { return "Unsplash" }
        if host.contains("freepik.com") { return "Freepik" }
        if host.contains("gofullpage") { return "GoFullPage" }

        // Generic domain cleaner (e.g. "cdn.example.org" -> "Example")
        let components = host.components(separatedBy: ".")
        if components.count >= 2 {
            let primary = components[components.count - 2]
            if primary.count > 2 {
                return primary.prefix(1).uppercased() + primary.dropFirst()
            }
        }

        return host
    }

    private static func cleanAppName(_ name: String) -> String {
        switch name {
        case "com.apple.Safari", "Safari": return "Safari"
        case "com.google.Chrome", "Google Chrome": return "Google Chrome"
        case "org.mozilla.firefox", "Firefox": return "Firefox"
        case "com.brave.Browser", "Brave": return "Brave"
        case "com.tinyspeck.slackmacgap", "Slack": return "Slack"
        case "com.hnc.Discord", "Discord": return "Discord"
        case "ru.keepcoder.Telegram", "Telegram": return "Telegram"
        default:
            return name
        }
    }
}
