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
    private(set) var jobs: [ActiveJob] = []

    // Persistent completed tail — seeded from API on launch, then kept
    // alive in-memory. Jobs that vanish from active are frozen into here
    // immediately so there is never a blank gap during API lag.
    private var completedTail: [ActiveJob] = []
    private var isFirstFetch = true

    // Previous poll snapshot — used to detect jobs that just finished
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
        let snapPrevJobs = prevActiveJobs
        let snapTail     = completedTail
        let firstFetch   = isFirstFetch

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

            // ── Jobs that were active last poll but are gone now — freeze immediately
            let now = Date()
            let vanished: [ActiveJob] = snapPrevJobs
                .filter { !activeIDs.contains($0.id) }
                .map { job in ActiveJob(
                    id: job.id, name: job.name, status: "completed", conclusion: "success",
                    startedAt: job.startedAt, createdAt: job.createdAt,
                    completedAt: now, isDimmed: true
                )}

            // ── API completed tail
            var apiTail: [ActiveJob] = []
            for scope in ScopeStore.shared.scopes { apiTail.append(contentsOf: fetchRecentCompletedJobs(for: scope)) }

            // ── Build new tail:
            // 1. Jobs just vanished — freeze + merge with existing tail
            // 2. First launch or empty tail — always seed from API
            // 3. Subsequent polls — replace only if API has new IDs
            // 4. API empty (lag) — keep existing tail unchanged
            let newTail: [ActiveJob]
            if !vanished.isEmpty {
                var merged = vanished
                for job in snapTail where !merged.contains(where: { $0.id == job.id }) { merged.append(job) }
                newTail = Array(merged.prefix(3))
            } else if firstFetch || snapTail.isEmpty {
                newTail = Array(apiTail.prefix(3))
            } else if !apiTail.isEmpty {
                let apiIDs  = Set(apiTail.map { $0.id })
                let tailIDs = Set(snapTail.map { $0.id })
                newTail = apiIDs.isSubset(of: tailIDs) ? snapTail : Array(apiTail.prefix(3))
            } else {
                newTail = snapTail
            }

            let merged = Array((activeJobs + newTail).prefix(3))
            log("RunnerStore › done — \(enriched.count) runners, \(activeJobs.count) active, \(newTail.count) tail, \(merged.count) shown")

            DispatchQueue.main.async {
                self.runners        = enriched
                self.jobs           = merged
                self.completedTail  = newTail
                self.prevActiveJobs = activeJobs
                self.isFirstFetch   = false
                self.onChange?()
            }
        }
    }
}
