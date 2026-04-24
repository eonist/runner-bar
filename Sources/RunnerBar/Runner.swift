import Foundation

struct Runner: Codable, Identifiable {
    let id: Int
    let name: String
    let status: String  // "online" or "offline"
    let busy: Bool

    var displayStatus: String {
        if status == "offline" { return "offline" }
        if busy {
            if let m = fetchMetrics(for: name) {
                return "active (CPU: \(m.cpu)% MEM: \(m.mem)%)"
            }
            return "active"
        }
        return "idle"
    }
}

private struct RunnersResponse: Codable {
    let runners: [Runner]
}
