import Foundation
import AppKit

enum AggregateStatus {
    case allOnline
    case someOffline
    case allOffline

    var dot: String {
        switch self {
        case .allOnline:   return "🟢"
        case .someOffline: return "🟡"
        case .allOffline:  return "⚫"
        }
    }

    var symbolName: String {
        switch self {
        case .allOnline:   return "circle.fill"
        case .someOffline: return "circle.lefthalf.filled"
        case .allOffline:  return "circle"
        }
    }
}

final class RunnerStore {
    static let shared = RunnerStore()

    private(set) var runners: [Runner] = []
    private(set) var jobs: [ActiveJob] = []
    private var timer: Timer?
    var onChange: (() -> Void)?

    var aggregateStatus: AggregateStatus {
        guard !runners.isEmpty else { return .allOffline }
        let onlineCount = runners.filter { $0.status == "online" }.count
        if onlineCount == runners.count { return .allOnline }
        if onlineCount == 0             { return .allOffline }
        return .someOffline
    }

    func start() {
        log("RunnerStore › start — poll interval 30s")
        timer?.invalidate()
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    func fetch() {
        log("RunnerStore › fetch — \(ScopeStore.shared.scopes.count) scope(s)")
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }

            // ── Runners ──────────────────────────────────────────────
            var all: [Runner] = []
            for scope in ScopeStore.shared.scopes {
                all.append(contentsOf: fetchRunners(for: scope))
            }
            let workerMetrics = allWorkerMetrics()
            var busyRunners = all.filter {  $0.busy }
            var idleRunners = all.filter { !$0.busy }
            for i in busyRunners.indices {
                busyRunners[i].metrics = i < workerMetrics.count ? workerMetrics[i] : nil
            }
            let offset = busyRunners.count
            for i in idleRunners.indices {
                let slot = offset + i
                idleRunners[i].metrics = slot < workerMetrics.count ? workerMetrics[slot] : nil
            }
            let enriched = busyRunners + idleRunners

            // ── Active jobs ──────────────────────────────────────────
            var activeJobs: [ActiveJob] = []
            for scope in ScopeStore.shared.scopes {
                activeJobs.append(contentsOf: fetchActiveJobs(for: scope))
            }

            // ── Completed tail ────────────────────────────────────
            var completedTail: [ActiveJob] = []
            for scope in ScopeStore.shared.scopes {
                completedTail.append(contentsOf: fetchRecentCompletedJobs(for: scope))
            }

            // Always merge: active first, then completed tail, cap at 3 total.
            // If completed fetch returned nothing (GitHub API lag), preserve
            // previous completed jobs (already dimmed+frozen) as the tail.
            let prevCompleted = self.jobs.filter { $0.isDimmed }
            let tail = completedTail.isEmpty ? prevCompleted : Array(completedTail.prefix(3))
            let merged = Array((activeJobs + tail).prefix(3))

            log("RunnerStore › fetch complete — \(enriched.count) runner(s), \(merged.count) job(s) (\(activeJobs.count) active, \(tail.count) tail)")

            DispatchQueue.main.async {
                self.runners = enriched
                self.jobs    = merged
                self.onChange?()
            }
        }
    }
}
