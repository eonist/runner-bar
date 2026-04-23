import Foundation

func githubToken() -> String? {
    // 1. gh CLI
    let token = shell("/opt/homebrew/bin/gh auth token")
    if !token.isEmpty && !token.hasPrefix("error") {
        return token
    }
    // 2. GH_TOKEN env var
    if let t = ProcessInfo.processInfo.environment["GH_TOKEN"], !t.isEmpty {
        return t
    }
    // 3. GITHUB_TOKEN env var
    if let t = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !t.isEmpty {
        return t
    }
    return nil
}
