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

// MARK: - Fetch steps

/// Fetches steps for a given job ID using the gh CLI.
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

// MARK: - Fetch step log

/// Downloads the full job log, extracts lines belonging to the given step number,
/// strips ANSI escape codes, and returns the last `maxLines` lines.
/// Returns (lines, wasTruncated).
func fetchStepLog(jobID: Int, stepNumber: Int, scope: String, maxLines: Int = 200) -> ([String], Bool) {
    guard scope.contains("/") else { return ([], false) }
    let parts = scope.split(separator: "/", maxSplits: 1)
    guard parts.count == 2 else { return ([], false) }
    let owner = String(parts[0])
    let repo  = String(parts[1])

    guard let data = ghAPI("repos/\(owner)/\(repo)/actions/jobs/\(jobID)/logs"),
          let raw  = String(data: data, encoding: .utf8)
    else {
        log("fetchStepLog › failed for job \(jobID) step \(stepNumber)")
        return ([], false)
    }

    // GitHub job logs are grouped by step with headers:
    // "##[group]Step N: <name>" … "##[endgroup]"
    // Each line is prefixed with a timestamp: "2024-01-01T00:00:00.0000000Z "
    let allLines = raw.components(separatedBy: "\n")

    // Extract lines for the target step
    var capturing = false
    var stepLines: [String] = []
    let stepPrefix = "##[group]Step \(stepNumber):"

    for line in allLines {
        // Strip timestamp prefix (29 chars: "YYYY-MM-DDTHH:MM:SS.fffffffZ ")
        let stripped = stripTimestamp(line)

        if stripped.hasPrefix(stepPrefix) {
            capturing = true
            continue
        }
        if capturing {
            if stripped.hasPrefix("##[endgroup]") {
                break
            }
            stepLines.append(stripANSI(stripped))
        }
    }

    // Fallback: if step grouping markers not found, return all lines stripped
    if stepLines.isEmpty && !allLines.isEmpty {
        stepLines = allLines.map { stripANSI(stripTimestamp($0)) }.filter { !$0.isEmpty }
    }

    let wasTruncated = stepLines.count > maxLines
    let result = wasTruncated ? Array(stepLines.suffix(maxLines)) : stepLines
    log("fetchStepLog › \(result.count) lines for job \(jobID) step \(stepNumber) (truncated: \(wasTruncated))")
    return (result, wasTruncated)
}

// MARK: - Log helpers

private func stripTimestamp(_ line: String) -> String {
    // Timestamps are ISO8601 with 7 fractional digits + space = 29 chars
    guard line.count > 29 else { return line }
    let start = line.index(line.startIndex, offsetBy: 29)
    // Validate it looks like a timestamp
    if line.first?.isNumber == true {
        return String(line[start...])
    }
    return line
}

private func stripANSI(_ input: String) -> String {
    // Remove ESC[ ... m sequences
    var result = input
    while let range = result.range(of: "\u{1B}\\[[0-9;]*[mGKHF]", options: .regularExpression) {
        result.removeSubrange(range)
    }
    // Remove ##[debug], ##[warning], ##[error], ##[command] prefixes
    let ghPrefixes = ["##[debug]", "##[warning]", "##[error]", "##[command]", "##[section]"]
    for prefix in ghPrefixes where result.hasPrefix(prefix) {
        result = String(result.dropFirst(prefix.count))
    }
    return result
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
