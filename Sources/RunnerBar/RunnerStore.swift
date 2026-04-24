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

    /// Persists completed jobs keyed by job id.
    /// Updated every poll: jobs with conclusion != nil from active runs
    /// are added here as dimmed frozen entries.
    private var completedCache: [Int: ActiveJob] = [:]

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

            let snapshotCache: [Int: ActiveJob] = DispatchQueue.main.sync { self.completedCache }

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
                idleRunners[i].metrics = (offset + i) < workerMetrics.count ? workerMetrics[offset + i] : nil
            }
            let enriched = busyRunners + idleRunners

            // ── All jobs from active runs ───────────────────────────
            var allFetched: [ActiveJob] = []
            for scope in ScopeStore.shared.scopes {
                allFetched.append(contentsOf: fetchActiveJobs(for: scope))
            }

            // Split: truly active (no conclusion) vs just-finished (has conclusion)
            let activeJobs   = allFetched.filter { $0.conclusion == nil }
            let finishedNow  = allFetched.filter { $0.conclusion != nil }

            // ── Update completed cache ─────────────────────────────
            var newCache = snapshotCache
            let activeIDs = Set(activeJobs.map { $0.id })

            // Add just-finished jobs into cache as dimmed frozen entries
            for job in finishedNow {
                guard newCache[job.id] == nil else { continue } // already cached
                newCache[job.id] = ActiveJob(
                    id:          job.id,
                    name:        job.name,
                    status:      "completed",
                    conclusion:  job.conclusion,
                    startedAt:   job.startedAt,
                    createdAt:   job.createdAt,
                    completedAt: job.completedAt ?? Date(),
                    isDimmed:    true
                )
            }
            // Remove from cache any job that is active again
            for id in activeIDs { newCache.removeValue(forKey: id) }

            // ── Build final list (max 3) ───────────────────────────
            // Priority: in_progress → queued → completed (dimmed), max 3 total
            let sorted = activeJobs.sorted { jobRank($0) < jobRank($1) }
            let active  = Array(sorted.prefix(3))
            let remaining = 3 - active.count
            var cached: [ActiveJob] = []
            if remaining > 0 {
                cached = newCache.values
                    .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                    .filter { !activeIDs.contains($0.id) }
                    .prefix(remaining)
                    .map { $0 }
            }
            let merged = active + cached

            log("RunnerStore › \(enriched.count) runner(s) | \(active.count) active + \(cached.count) cached = \(merged.count) | cache: \(newCache.count)")

            DispatchQueue.main.async {
                self.runners        = enriched
                self.jobs           = merged
                self.completedCache = newCache
                self.onChange?()
            }
        }
    }
}

func jobRank(_ job: ActiveJob) -> Int {
    switch job.status {
    case "in_progress": return 0
    case "queued":      return 1
    default:            return 2
    }
}
