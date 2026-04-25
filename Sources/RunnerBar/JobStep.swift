import Foundation

// MARK: - Model

struct JobStep: Identifiable {
    let id: Int           // step number (1-based)
    let name: String
    let status: String    // queued | in_progress | completed
    let conclusion: String?
    let startedAt: Date?
    let completedAt: Date?

    var isSkipped: Bool { conclusion == "skipped" }
    var isDimmed: Bool  { conclusion == "skipped" || conclusion == "cancelled" }

    /// queued → “00:00” | in_progress → live | completed → frozen duration
    var elapsed: String {
        guard status != "queued" else { return "00:00" }
        guard let start = startedAt else { return "00:00" }
        let end = completedAt ?? Date()
        let sec = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%02d:%02d", sec / 60, sec % 60)
    }
}

// MARK: - Fetch

/// Fetches steps for a given job ID using the gh CLI.
/// Returns an empty array on any error.
func fetchJobSteps(jobID: Int, scope: String) -> [JobStep] {
    guard scope.contains("/") else { return [] }
    let parts = scope.split(separator: "/", maxSplits: 1)
    guard parts.count == 2 else { return [] }
    let owner = String(parts[0])
    let repo  = String(parts[1])

    guard
        let data = ghAPI("repos/\(owner)/\(repo)/actions/jobs/\(jobID)"),
        let resp = try? JSONDecoder().decode(JobDetailResponse.self, from: data)
    else {
        log("fetchJobSteps › failed for job \(jobID)")
        return []
    }

    let iso = ISO8601DateFormatter()
    let steps: [JobStep] = resp.steps.map { s in
        JobStep(
            id:          s.number,
            name:        s.name,
            status:      s.status,
            conclusion:  s.conclusion,
            startedAt:   s.startedAt.flatMap   { iso.date(from: $0) },
            completedAt: s.completedAt.flatMap { iso.date(from: $0) }
        )
    }
    log("fetchJobSteps › \(steps.count) steps for job \(jobID)")
    return steps
}

// MARK: - Codable helpers

private struct JobDetailResponse: Codable {
    let steps: [StepPayload]
}

private struct StepPayload: Codable {
    let number: Int
    let name: String
    let status: String
    let conclusion: String?
    let startedAt: String?
    let completedAt: String?
    enum CodingKeys: String, CodingKey {
        case number, name, status, conclusion
        case startedAt   = "started_at"
        case completedAt = "completed_at"
    }
}
