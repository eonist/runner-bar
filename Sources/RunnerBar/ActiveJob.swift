import Foundation

// MARK: - Model

struct ActiveJob: Identifiable {
    let id: Int
    let name: String
    let status: String       // "queued", "in_progress", "completed"
    let conclusion: String?  // "success", "failure", "cancelled", nil
    let startedAt: Date?     // nil for queued jobs — fall back to createdAt
    let createdAt: Date?

    /// Elapsed time since the job started (or was created if not yet started).
    var elapsed: String {
        guard let start = startedAt ?? createdAt else { return "—" }
        let sec = Int(Date().timeIntervalSince(start))
        guard sec >= 0 else { return "—" }
        let m = sec / 60; let s = sec % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Fetch

/// Fetches in_progress AND queued workflow runs for `scope`, collects all
/// their jobs, deduplicates by job id, and sorts: in_progress → queued → done.
func fetchActiveJobs(for scope: String) -> [ActiveJob] {
    guard scope.contains("/") else {
        log("fetchActiveJobs › org-level runs not supported, skipping \(scope)")
        return []
    }

    let iso = ISO8601DateFormatter()
    var runIDs: [Int] = []
    var seenRunIDs = Set<Int>()

    // Fetch both statuses so we get queued jobs too
    for status in ["in_progress", "queued"] {
        let path = "/repos/\(scope)/actions/runs?status=\(status)&per_page=10"
        log("fetchActiveJobs › fetching \(status) runs: \(path)")
        let json = shell("/opt/homebrew/bin/gh api \(path)")
        guard
            let data = json.data(using: .utf8),
            let resp = try? JSONDecoder().decode(WorkflowRunsResponse.self, from: data)
        else {
            log("fetchActiveJobs › failed to decode \(status) runs for \(scope)")
            continue
        }
        log("fetchActiveJobs › \(resp.workflowRuns.count) \(status) run(s)")
        for run in resp.workflowRuns {
            if seenRunIDs.insert(run.id).inserted {
                runIDs.append(run.id)
            }
        }
    }

    var jobs: [ActiveJob] = []
    var seenJobIDs = Set<Int>()

    for runID in runIDs {
        let path = "/repos/\(scope)/actions/runs/\(runID)/jobs?per_page=30"
        let json = shell("/opt/homebrew/bin/gh api \(path)")
        guard
            let data = json.data(using: .utf8),
            let resp = try? JSONDecoder().decode(JobsResponse.self, from: data)
        else {
            log("fetchActiveJobs › failed to decode jobs for run \(runID)")
            continue
        }
        for j in resp.jobs {
            guard seenJobIDs.insert(j.id).inserted else { continue }
            jobs.append(ActiveJob(
                id:         j.id,
                name:       j.name,
                status:     j.status,
                conclusion: j.conclusion,
                startedAt:  j.startedAt.flatMap  { iso.date(from: $0) },
                createdAt:  j.createdAt.flatMap  { iso.date(from: $0) }
            ))
        }
    }

    log("fetchActiveJobs › \(jobs.count) total job(s) for \(scope)")
    return jobs.sorted { rank($0) < rank($1) }
}

private func rank(_ job: ActiveJob) -> Int {
    switch job.status {
    case "in_progress": return 0
    case "queued":      return 1
    default:            return 2
    }
}

// MARK: - Codable helpers

private struct WorkflowRunsResponse: Codable {
    let workflowRuns: [WorkflowRun]
    enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" }
}
private struct WorkflowRun: Codable { let id: Int }
private struct JobsResponse: Codable { let jobs: [JobPayload] }
private struct JobPayload: Codable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let startedAt: String?
    let createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion
        case startedAt = "started_at"
        case createdAt = "created_at"
    }
}
