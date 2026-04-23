import Foundation

func fetchRunners(for scope: String) -> [Runner] {
    let path: String
    if scope.contains("/") {
        path = "/repos/\(scope)/actions/runners"
    } else {
        path = "/orgs/\(scope)/actions/runners"
    }

    print("[RunnerBar] fetching: \(path)")
    let json = shell("/opt/homebrew/bin/gh api \(path)")
    print("[RunnerBar] response: \(json.prefix(200))")

    guard
        let data = json.data(using: .utf8),
        let response = try? JSONDecoder().decode(RunnersResponse.self, from: data)
    else {
        print("[RunnerBar] decode failed for scope: \(scope)")
        return []
    }

    print("[RunnerBar] found \(response.runners.count) runners for \(scope)")
    return response.runners
}

private struct RunnersResponse: Codable {
    let runners: [Runner]
}
