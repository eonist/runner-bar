import Foundation

// MARK: - Runners

func fetchRunners(for scope: String) -> [Runner] {
    let path: String
    if scope.contains("/") {
        path = "/repos/\(scope)/actions/runners"
    } else {
        path = "/orgs/\(scope)/actions/runners"
    }

    log("fetchRunners › \(path)")
    let json = shell("/opt/homebrew/bin/gh api \(path)")
    log("fetchRunners › response prefix: \(json.prefix(120))")

    guard
        let data = json.data(using: .utf8),
        let response = try? JSONDecoder().decode(RunnersResponse.self, from: data)
    else {
        log("fetchRunners › decode failed for scope: \(scope)")
        return []
    }

    log("fetchRunners › found \(response.runners.count) runner(s) for \(scope)")
    return response.runners
}

private struct RunnersResponse: Codable {
    let runners: [Runner]
}

// MARK: - Step log

/// Fetch and slice the raw log for a single step.
///
/// GitHub returns the full job log as one raw text blob from:
///   GET /repos/{owner}/{repo}/actions/jobs/{job_id}/logs
///
/// The blob is structured by GitHub Actions group markers:
///   ##[group]Step Name
///   ... log lines ...
///   ##[endgroup]
///
/// Each ##[group] marker corresponds to one step in order.
/// stepNumber is 1-based (matches JobStep.id).
///
/// Returns nil if:
///   - scope is not repo-scoped (org-scoped logs are not supported)
///   - gh CLI fails or returns no data
///   - stepNumber is out of range
///
/// ⚠️ This function is synchronous and MUST be called from a background thread.
///    Always dispatch via DispatchQueue.global() before calling.
func fetchStepLog(jobID: Int, stepNumber: Int, scope: String) -> String? {
    guard scope.contains("/") else {
        log("fetchStepLog › skipped: org-scoped logs not supported (scope=\(scope))")
        return nil
    }

    let gh = "/opt/homebrew/bin/gh"
    guard FileManager.default.isExecutableFile(atPath: gh) else {
        log("fetchStepLog › gh not found at \(gh)")
        return nil
    }

    let endpoint = "repos/\(scope)/actions/jobs/\(jobID)/logs"
    log("fetchStepLog › fetching \(endpoint) step=\(stepNumber)")

    // gh api returns the raw log text (not JSON) for this endpoint.
    // We use shell() which captures stdout as a String.
    let raw = shell("\(gh) api \(endpoint)")
    guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        log("fetchStepLog › empty response for job \(jobID)")
        return nil
    }

    // Split into per-step sections by ##[group] markers.
    // Each section starts at a ##[group] line and ends just before the next one
    // (or at end-of-string). The ##[endgroup] lines are included as part of each
    // section and are not used as delimiters.
    let lines = raw.components(separatedBy: "\n")
    var sections: [String] = []
    var current: [String] = []

    for line in lines {
        if line.hasPrefix("##[group]") {
            if !current.isEmpty {
                sections.append(current.joined(separator: "\n"))
            }
            current = [line]
        } else {
            current.append(line)
        }
    }
    if !current.isEmpty {
        sections.append(current.joined(separator: "\n"))
    }

    // stepNumber is 1-based; sections array is 0-based.
    // If log has no ##[group] markers (old format), return entire log for step 1 only.
    if sections.isEmpty || (sections.count == 1 && !sections[0].hasPrefix("##[group]")) {
        log("fetchStepLog › no group markers, returning raw log")
        return stepNumber == 1 ? raw : nil
    }

    let index = stepNumber - 1
    guard index >= 0, index < sections.count else {
        log("fetchStepLog › stepNumber \(stepNumber) out of range (sections=\(sections.count))")
        return nil
    }

    let section = sections[index]
    log("fetchStepLog › step \(stepNumber) → \(section.count)ch")
    return section
}
