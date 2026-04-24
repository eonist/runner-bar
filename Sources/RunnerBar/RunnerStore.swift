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
    /// Last active jobs seen — used to seed completed tail during API lag.
    private var lastActiveJobs: [ActiveJob] = []
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

            let prevActive: [ActiveJob] = DispatchQueue.main.sync { self.lastActiveJobs }

            // ── Runners ──────────────────────────────────────────
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

            // ── Active jobs (in_progress + queued, conclusion == nil) ───
            var activeJobs: [ActiveJob] = []
            for scope in ScopeStore.shared.scopes {
                activeJobs.append(contentsOf: fetchActiveJobs(for: scope))
            }
            // Priority: in_progress first, then queued — cap at 3
            let active = Array(activeJobs.sorted { rank($0) < rank($1) }.prefix(3))
            let activeIDs = Set(active.map { $0.id })

            // ── Completed tail — fills remaining slots up to 3 ───────
            let remaining = 3 - active.count
            var tail: [ActiveJob] = []

            if remaining > 0 {
                // 1. Try fresh API completed data
                var apiTail: [ActiveJob] = []
                for scope in ScopeStore.shared.scopes {
                    apiTail.append(contentsOf: fetchRecentCompletedJobs(for: scope))
                }
                let freshTail = apiTail.filter { !activeIDs.contains($0.id) }

                if !freshTail.isEmpty {
                    tail = Array(freshTail.prefix(remaining))
                } else {
                    // 2. API lag: use previously dimmed jobs still in store
                    let existingDimmed = DispatchQueue.main.sync {
                        self.jobs.filter { $0.isDimmed && !activeIDs.contains($0.id) }
                    }
                    if !existingDimmed.isEmpty {
                        tail = Array(existingDimmed.prefix(remaining))
                    } else if !prevActive.isEmpty {
                        // 3. Jobs just vanished from active — freeze them as dimmed
                        let now = Date()
                        tail = Array(prevActive
                            .filter { !activeIDs.contains($0.id) }
                            .map { job in
                                ActiveJob(
                                    id:          job.id,
                                    name:        job.name,
                                    status:      "completed",
                                    conclusion:  "success",
                                    startedAt:   job.startedAt,
                                    createdAt:   job.createdAt,
                                    completedAt: now,
                                    isDimmed:    true
                                )
                            }
                            .prefix(remaining))
                    }
                }
            }

            // Final list: in_progress → queued → completed (dimmed), max 3
            let merged = active + tail

            log("RunnerStore › \(enriched.count) runner(s) | \(active.count) active + \(tail.count) done = \(merged.count) job(s)")

            DispatchQueue.main.async {
                self.runners       = enriched
                self.jobs          = merged
                self.lastActiveJobs = activeJobs
                self.onChange?()
            }
        }
    }
}

private func rank(_ job: ActiveJob) -> Int {
    switch job.status {
    case "in_progress": return 0
    case "queued":      return 1
    default:            return 2
    }
}
