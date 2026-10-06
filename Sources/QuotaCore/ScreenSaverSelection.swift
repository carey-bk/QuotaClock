import Foundation

/// Read the modern system selection without writing undocumented Wallpaper settings.
/// Unknown layouts return nil instead of claiming that installation means activation.
public enum ScreenSaverSelection {
    public static func isQuotaClock(in data: Data) -> Bool? {
        guard let store = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let global = store["AllSpacesAndDisplays"] as? [String: Any],
              let idle = global["Idle"] as? [String: Any],
              let content = idle["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]], !choices.isEmpty else { return nil }
        var matches: [Bool] = []
        for choice in choices {
            guard choice["Provider"] as? String == "com.apple.wallpaper.choice.screen-saver" else { matches.append(false); continue }
            guard let config = choice["Configuration"] as? Data,
                  let dictionary = try? PropertyListSerialization.propertyList(from: config, format: nil) as? [String: Any],
                  let module = dictionary["module"] as? [String: Any],
                  let relative = module["relative"] as? String, let url = URL(string: relative) else { return nil }
            matches.append(url.lastPathComponent == "QuotaClock.saver")
        }
        return matches.allSatisfy { $0 }
    }
}
