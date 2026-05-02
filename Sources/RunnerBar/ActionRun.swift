import Foundation

// MARK: - ActionRun

/// Represents a single GitHub Actions workflow run (e.g. "SonarQube", "vitest").
/// Contains the ordered list of jobs that belong to this run.
///
/// Design intent: ActionRun is the parent of ActiveJob. The existing Active Jobs
/// section shows all jobs flat; this Actions section groups them by workflow run.
/// The two sections share the same underlying job model (ActiveJob) so all
/// existing step/log navigation reuses existing views without modification.
struct ActionRun: Identifiable {
    let id: Int              // workflow run_id — stable key across polls
    let name: String         // workflow name (e.g. "SonarQube", "vitest", "ui-tests")
    let repo: String         // owner/repo slug
    let status: String       // queued | in_progress | completed
    let conclusion: String?  // success | failure | cancelled | skipped (nil while live)
    let headBranch: String?
    let createdAt: Date?
    let updatedAt: Date?
    let htmlUrl: String?
    var jobs: [ActiveJob] = []   // populated by fetchJobsForRun(_:scope:iso:)
    var isDimmed: Bool = false   // true when completed and frozen into actionCache

    /// Human-readable elapsed time for the run, mirrors ActiveJob.elapsed logic.
    var elapsed: String {
        guard status != "queued" else { return "00:00" }
        if conclusion != nil {
            guard let start = createdAt, let end = updatedAt else { return "--:--" }
            let sec = Int(end.timeIntervalSince(start))
            guard sec >= 0 else { return "--:--" }
            let m = sec / 60; let s = sec % 60
            return String(format: "%02d:%02d", m, s)
        }
        guard let start = createdAt else { return "00:00" }
        let sec = Int(Date().timeIntervalSince(start))
        guard sec >= 0 else { return "00:00" }
        let m = sec / 60; let s = sec % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// "done / total" job progress string, e.g. "2/4".
    var jobProgress: String {
        let done = jobs.filter { $0.conclusion != nil }.count
        return "\(done)/\(jobs.count)"
    }
}

// MARK: - Codable helpers (private to this file)

private struct ActionRunsResponse: Codable {
    let workflowRuns: [RunPayload]
    enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" }
}

private struct RunPayload: Codable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let headBranch: String?
    let createdAt: String?
    let updatedAt: String?
    let htmlUrl: String?
    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion
        case headBranch = "head_branch"
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
        case htmlUrl    = "html_url"
    }
}

// MARK: - Fetch

/// Fetches active (in_progress + queued) workflow runs for a repo scope,
/// enriching each with its list of jobs by reusing the existing JobsResponse
/// decoder from ActiveJob.swift.
///
/// Org scopes are skipped — the GitHub API requires a repo-scoped endpoint for
/// per-run job lists, consistent with how fetchActiveJobs handles org scopes.
func fetchActions(for scope: String) -> [ActionRun] {
    guard scope.contains("/") else {
        log("fetchActions › skipping org scope \(scope)")
        return []
    }

    let iso = ISO8601DateFormatter()
    var runs: [ActionRun] = []
    var seenIDs = Set<Int>()

    for status in ["in_progress", "queued"] {
        let endpoint = "repos/\(scope)/actions/runs?status=\(status)&per_page=20"
        guard
            let data = ghAPI(endpoint),
            let resp = try? JSONDecoder().decode(ActionRunsResponse.self, from: data)
        else { continue }

        for run in resp.workflowRuns {
            guard seenIDs.insert(run.id).inserted else { continue }
            let jobs = fetchJobsForRun(run.id, scope: scope, iso: iso)
            runs.append(ActionRun(
                id:         run.id,
                name:       run.name,
                repo:       scope,
                status:     run.status,
                conclusion: run.conclusion,
                headBranch: run.headBranch,
                createdAt:  run.createdAt.flatMap { iso.date(from: $0) },
                updatedAt:  run.updatedAt.flatMap { iso.date(from: $0) },
                htmlUrl:    run.htmlUrl,
                jobs:       jobs
            ))
        }
    }

    log("fetchActions › \(runs.count) run(s) for \(scope)")
    return runs
}

// MARK: - Private helpers

/// Fetches the job list for a single workflow run, reusing the internal
/// JobsResponse / JobPayload / StepPayload codables from ActiveJob.swift.
private func fetchJobsForRun(_ runID: Int, scope: String, iso: ISO8601DateFormatter) -> [ActiveJob] {
    guard
        let data = ghAPI("repos/\(scope)/actions/runs/\(runID)/jobs?per_page=100"),
        let resp = try? JSONDecoder().decode(JobsResponse.self, from: data)
    else { return [] }

    return resp.jobs.map { j in
        let steps: [JobStep] = (j.steps ?? []).enumerated().map { idx, s in
            JobStep(
                id:          idx + 1,
                name:        s.name,
                status:      s.status,
                conclusion:  s.conclusion,
                startedAt:   s.startedAt.flatMap   { iso.date(from: $0) },
                completedAt: s.completedAt.flatMap  { iso.date(from: $0) }
            )
        }
        // NOTE: ActiveJob construction here is intentional — ActionRun holds
        // [ActiveJob] so that ActionDetailView → JobDetailView → StepLogView
        // reuses existing views without any modification.
        return ActiveJob(
            id:          j.id,
            name:        j.name,
            status:      j.status,
            conclusion:  j.conclusion,
            startedAt:   j.startedAt.flatMap   { iso.date(from: $0) },
            createdAt:   j.createdAt.flatMap   { iso.date(from: $0) },
            completedAt: j.completedAt.flatMap { iso.date(from: $0) },
            htmlUrl:     j.htmlUrl,
            steps:       steps
        )
    }
}
