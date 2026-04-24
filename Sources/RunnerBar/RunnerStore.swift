import Foundation
import AppKit

enum AggregateStatus {
    case allOnline, someOffline, allOffline
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
    private(set) var jobs: [ActiveJob] = []          // what the UI sees (max 3)

    // Persistent completed tail — never cleared, only updated.
    // Survives API lag because we seed it from in-memory active jobs
    // the moment they disappear, before the API catches up.
    private var completedTail: [ActiveJob] = []

    // Active jobs from the previous poll cycle — used to detect vanished jobs
    private var prevActiveIDs: Set<Int> = []
    private var prevActiveJobs: [ActiveJob] = []

    private var timer: Timer?
    var onChange: (() -> Void)?

    var aggregateStatus: AggregateStatus {
        guard !runners.isEmpty else { return .allOffline }
        let n = runners.filter { $0.status == "online" }.count
        if n == runners.count { return .allOnline }
        if n == 0             { return .allOffline }
        return .someOffline
    }

    func start() {
        log("RunnerStore › start")
        timer?.invalidate()
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.fetch() }
    }

    func fetch() {
        log("RunnerStore › fetch")
        // Capture prev state on main thread before going background
        let snapPrevIDs  = prevActiveIDs
        let snapPrevJobs = prevActiveJobs
        let snapTail     = completedTail

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }

            // ── Runners
            var all: [Runner] = []
            for scope in ScopeStore.shared.scopes { all.append(contentsOf: fetchRunners(for: scope)) }
            let metrics = allWorkerMetrics()
            var busy = all.filter { $0.busy }; var idle = all.filter { !$0.busy }
            for i in busy.indices { busy[i].metrics = i < metrics.count ? metrics[i] : nil }
            for i in idle.indices { let s = busy.count + i; idle[i].metrics = s < metrics.count ? metrics[s] : nil }
            let enriched = busy + idle

            // ── Active jobs this cycle
            var activeJobs: [ActiveJob] = []
            for scope in ScopeStore.shared.scopes { activeJobs.append(contentsOf: fetchActiveJobs(for: scope)) }
            let activeIDs = Set(activeJobs.map { $0.id })

            // ── Detect vanished jobs: were active last cycle, gone now
            // Freeze them immediately as dimmed+completed so tail never gaps
            let now = Date()
            let vanished: [ActiveJob] = snapPrevJobs
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

            // ── Try to get fresh completed tail from API
            var apiTail: [ActiveJob] = []
            for scope in ScopeStore.shared.scopes { apiTail.append(contentsOf: fetchRecentCompletedJobs(for: scope)) }

            // ── Build new completed tail:
            // Merge vanished jobs + existing tail, deduplicate by id, keep 3.
            // Replace with fresh API tail only if it contains jobs we haven't
            // seen before (prevents stale API data from overwriting session jobs).
            var newTail: [ActiveJob]
            if !vanished.isEmpty {
                // Jobs just finished this cycle — prepend them, dedupe, cap 3
                var merged = vanished
                for job in snapTail where !merged.contains(where: { $0.id == job.id }) {
                    merged.append(job)
                }
                newTail = Array(merged.prefix(3))
            } else if !apiTail.isEmpty {
                // No vanished jobs; use API tail if it has new entries
                let apiIDs = Set(apiTail.map { $0.id })
                let tailIDs = Set(snapTail.map { $0.id })
                if !apiIDs.isSubset(of: tailIDs) || snapTail.isEmpty {
                    newTail = Array(apiTail.prefix(3))
                } else {
                    newTail = snapTail  // API has nothing new, keep existing
                }
            } else {
                newTail = snapTail  // API empty (lag), keep existing tail
            }

            // ── Build final job list: active first, then tail, cap 3
            // Priority: in_progress > queued > completed
            let merged = Array((activeJobs + newTail).prefix(3))

            log("RunnerStore › done — \(enriched.count) runners, \(activeJobs.count) active, \(newTail.count) tail, \(merged.count) shown")

            DispatchQueue.main.async {
                self.runners       = enriched
                self.jobs          = merged
                self.completedTail = newTail
                self.prevActiveIDs = activeIDs
                self.prevActiveJobs = activeJobs
                self.onChange?()
            }
        }
    }
}
