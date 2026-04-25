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
/// IMPORTANT: This endpoint redirects (302) to a pre-signed S3 URL.
/// The correct Accept header to get raw text is:
///   Accept: application/vnd.github.v3.raw
/// Without it, gh api may return an error JSON or empty string.
///
/// The log blob is structured by GitHub Actions group markers:
///   ##[group]Step Name
///   ... log lines ...
///   ##[endgroup]
///
/// Each ##[group] marker corresponds to one step in order.
/// stepNumber is 1-based (matches JobStep.id).
///
/// Returns nil if:
///   - scope is not repo-scoped (org-scoped logs are not supported by this API)
///   - gh CLI fails or returns no data
///   - stepNumber is out of range
///
/// ⚠️ MUST be called from a background thread. Always dispatch via DispatchQueue.global().
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

    // ⚠️ CRITICAL: Must include the raw Accept header.
    // Without it, gh api returns a redirect response or error JSON instead
    // of the actual log text. This was the primary cause of "Log not available".
    let raw = shell("\(gh) api \(endpoint) --header \"Accept: application/vnd.github.v3.raw\"")

    guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        log("fetchStepLog › empty response for job \(jobID)")
        return nil
    }

    // Detect error JSON (gh api returns {"message":"..."} on auth/404 errors)
    if raw.hasPrefix("{") {
        log("fetchStepLog › error JSON returned: \(raw.prefix(120))")
        return nil
    }

    // Strip ANSI escape codes (GitHub logs contain color codes like \033[32m)
    // that render as garbage characters in a plain SwiftUI Text view.
    let cleaned = stripAnsi(raw)

    // Split into per-step sections by ##[group] markers.
    // Each section starts at a ##[group] line and ends just before the next.
    // ##[endgroup] lines are included inside each section.
    let lines = cleaned.components(separatedBy: "\n")
    var sections: [String] = []
    var current: [String] = []

    for line in lines {
        if line.contains("##[group]") {
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

    log("fetchStepLog › parsed \(sections.count) section(s) from log")

    // If log has no ##[group] markers (old/simple format), return full log.
    if sections.isEmpty || (sections.count == 1 && !sections[0].contains("##[group]")) {
        log("fetchStepLog › no group markers, returning full raw log")
        return cleaned
    }

    // stepNumber is 1-based; sections array is 0-based.
    let index = stepNumber - 1
    guard index >= 0, index < sections.count else {
        log("fetchStepLog › stepNumber \(stepNumber) out of range (sections=\(sections.count)), returning full log")
        // Out of range: return full log rather than nil so user sees something
        return cleaned
    }

    let section = sections[index]
    log("fetchStepLog › step \(stepNumber) → \(section.count)ch")
    return section.isEmpty ? cleaned : section
}

/// Strip ANSI/VT100 escape sequences from a string.
/// GitHub Actions logs contain color codes (e.g. \033[32m) that appear as
/// garbage in a plain text view.
private func stripAnsi(_ input: String) -> String {
    // Matches ESC[ followed by any number of digits/semicolons and a letter
    guard let regex = try? NSRegularExpression(pattern: "\\x1B\\[[0-9;]*[A-Za-z]") else {
        return input
    }
    return regex.stringByReplacingMatches(
        in: input,
        range: NSRange(input.startIndex..., in: input),
        withTemplate: ""
    )
}
