import Foundation

struct Runner: Codable, Identifiable {
    let id: Int
    let name: String
    let status: String  // "online" or "offline"
    let busy: Bool

    var busyCount: Int = 1

    enum CodingKeys: String, CodingKey {
        case id, name, status, busy
    }

    var displayStatus: String {
        if status == "offline" { return "offline" }
        let m = fetchMetrics(for: name, busyCount: busyCount)
        let cpu = m?.cpu ?? 0
        let mem = m?.mem ?? 0
        let label = busy ? "active" : "idle"
        return "\(label) (CPU: \(cpu)% MEM: \(mem)%)"
    }
}

private struct RunnersResponse: Codable {
    let runners: [Runner]
}
