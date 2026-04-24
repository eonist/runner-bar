import Foundation

struct RunnerMetrics {
    let cpu: Int
    let mem: Int
}

/// Uses `ps` to find a Runner.Worker process whose args contain `runnerName`.
/// Returns nil if no matching process is found.
func fetchMetrics(for runnerName: String) -> RunnerMetrics? {
    let output = shell("ps -eo pcpu,pmem,args | grep 'Runner.Worker' | grep -v grep")
    guard !output.isEmpty else { return nil }
    for line in output.components(separatedBy: "\n") {
        guard line.contains(runnerName) else { continue }
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2,
              let cpu = Double(parts[0]),
              let mem = Double(parts[1]) else { continue }
        return RunnerMetrics(cpu: Int(cpu.rounded()), mem: Int(mem.rounded()))
    }
    return nil
}
