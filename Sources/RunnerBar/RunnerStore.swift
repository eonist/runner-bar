import Foundation
import AppKit

// MARK: - Aggregate status

/// Represents the combined online/offline status across all registered runners.
/// Drives the status bar icon colour so the user can see runner health at a glance.
enum AggregateStatus {
    /// All registered runners are online.
    case allOnline
    /// At least one runner is online and at least one is offline.
    case someOffline
    /// All registered runners are offline, or no runners are registered.
    case allOffline

    /// Emoji dot representation, used in log output for quick visual scanning.
    var dot: String {
        switch self {
        case .allOnline:   return "🟢"
        case .someOffline: return "🟡"
        case .allOffline:  return "⚫"
        }
    }

    /// SF Symbol name for use in SwiftUI `Image(systemName:)` calls.
    var symbolName: String {
        switch self {
        case .allOnline:   return "circle.fill"
        case .someOffline: return "circle.lefthalf.filled"
        case .allOffline:  return "circle"
        }
    }
}

// MARK: - Store

/// Singleton polling store that coordinates GitHub runner + job fetching every 10 seconds.
///
/// Owns the canonical `runners` and `jobs` arrays consumed by the UI layer.
/// Call `start()` once at launch (or whenever a new scope is added) to begin polling.
/// Subscribe to `onChange` to be notified after each poll completes.
final class RunnerStore {
    /// Shared singleton — the single source of truth for runner and job state.
    static let shared = RunnerStore()

    /// Currently known self-hosted runners, enriched with local process metrics.
    /// Updated on every poll. Must only be read and written on the main thread.
    private(set) var runners: [Runner] = []

    /// Jobs to display: live (in_progress/queued) + recently completed (dimmed).
    /// Capped at 3 entries. Updated on every poll. Main-thread only.
    private(set) var jobs: [ActiveJob] = []

    /// Workflow runs to display: live + recently completed (dimmed).
    /// Capped at 5 entries (matches ci-dash.py MAX_GROUPS). Main-thread only.
    private(set) var actions: [ActionRun] = []

    // ⚠️ REGRESSION GUARD — completed job persistence (ref issue #54)
    // prevLiveJobs: full snapshot of the LIVE jobs from the previous poll.
    //   Used to detect vanished jobs (were live, now gone) and freeze them into cache.
    // completedCache: the ONLY reliable source of done jobs.
    //   - NEVER clear this between polls — persistence depends on it surviving.
    //   - NEVER replace with fetchRecentCompletedJobs() alone — GitHub API lags
    //     10-30 seconds before marking a run 'completed', causing done jobs to vanish.
    //   - Jobs are frozen in from TWO sources every poll:
    //       a) jobs with conclusion != nil inside still-active runs (immediate)
    //       b) jobs that disappear from prevLiveJobs between polls (vanished)
    //   - Trimmed to newest 3 entries to cap memory.
    private var prevLiveJobs: [Int: ActiveJob] = [:]
    private var completedCache: [Int: ActiveJob] = [:]

    // ── Actions persistence (mirrors job cache pattern above)
    // prevLiveRuns: live ActionRun snapshot from previous poll — used to detect
    //   vanished runs and freeze them into actionCache.
    // actionCache: persists completed runs so they survive past the API disappearing.
    //   - NEVER clear between polls.
    //   - Trimmed to newest 5 entries (ci-dash.py MAX_GROUPS = 5).
    private var prevLiveRuns: [Int: ActionRun] = [:]
    private var actionCache:  [Int: ActionRun] = [:]

    /// The repeating 10-second poll timer. Held strongly so it is not deallocated.
    private var timer: Timer?

    /// Called on the main thread after each poll completes.
    /// Use this to trigger a UI refresh (e.g. reload the observable or update the icon).
    var onChange: (() -> Void)?

    /// Derives the aggregate runner status from the current `runners` array.
    /// Returns `.allOffline` when `runners` is empty (no scopes configured yet).
    var aggregateStatus: AggregateStatus {
        guard !runners.isEmpty else { return .allOffline }
        let online = runners.filter { $0.status == "online" }.count
        if online == runners.count { return .allOnline }
        if online == 0             { return .allOffline }
        return .someOffline
    }

    /// Starts (or restarts) the 10-second polling timer and fires an immediate fetch.
    /// Invalidates any existing timer first to prevent stacked timers when called
    /// multiple times (e.g. each time a new scope is added via `submitScope()`).
    func start() {
        log("RunnerStore › start")
        timer?.invalidate()  // ⚠️ Always invalidate before creating a new timer — prevents stacking
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    /// Fetches runners and active jobs for all scopes on a background thread.
    ///
    /// Algorithm:
    /// 1. Fetch runners via `fetchRunners(for:)` and enrich with local `ps aux` metrics.
    /// 2. Fetch active jobs via `fetchActiveJobs(for:)` for every scope.
    /// 3. Diff live jobs against `prevLiveJobs` to detect vanished jobs and freeze them
    ///    into `completedCache` (prevents done jobs from disappearing before the API
    ///    marks the run as completed, which can lag 10–30 s).
    /// 4. Add freshly-concluded jobs (conclusion != nil in still-active runs) to cache.
    /// 5. Trim cache to the 3 most-recently-completed jobs.
    /// 6. Build the display list: in_progress → queued → cached done (newest first),
    ///    capped at 3. This priority ensures actively-running jobs are always visible.
    /// 7. Publish all results to `runners`, `jobs`, `completedCache`, `prevLiveJobs`
    ///    on the main thread, then call `onChange`.
    func fetch() {
        // Snapshot all mutable state on the main thread BEFORE entering the
        // background block, mirroring the prevLiveJobs/completedCache pattern.
        // ⚠️ NEVER read self.prevLiveRuns/actionCache inside the background block
        //    directly — that would be a data race with the main-thread writes below.
        let snapPrev     = prevLiveJobs
        let snapCache    = completedCache
        let snapPrevRuns = prevLiveRuns
        let snapRunCache = actionCache

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }

            // ── Runners
            var allRunners: [Runner] = []
            for scope in ScopeStore.shared.scopes {
                allRunners.append(contentsOf: fetchRunners(for: scope))
            }
            let metrics = allWorkerMetrics()
            var busy = allRunners.filter { $0.busy }
            var idle = allRunners.filter { !$0.busy }
            // Assign metrics by slot index (busy first) — name-based matching is
            // not possible because runner names do not appear in ps aux output.
            for i in busy.indices { busy[i].metrics = i < metrics.count ? metrics[i] : nil }
            for i in idle.indices {
                let s = busy.count + i
                idle[i].metrics = s < metrics.count ? metrics[s] : nil
            }
            let enrichedRunners = busy + idle

            // ── Fetch jobs
            var allFetched: [ActiveJob] = []
            for scope in ScopeStore.shared.scopes {
                allFetched.append(contentsOf: fetchActiveJobs(for: scope))
            }

            let liveJobs  = allFetched.filter { $0.conclusion == nil }
            let freshDone = allFetched.filter { $0.conclusion != nil }
            let liveIDs   = Set(liveJobs.map { $0.id })
            let now       = Date()

            var newCache = snapCache

            // ⚠️ CALLSITE 2 of 3 — Vanished jobs: were live last poll, gone now.
            // Freeze with last known data. completedAt defaults to now if API had none.
            for (id, job) in snapPrev where !liveIDs.contains(id) {
                guard newCache[id] == nil else { continue }
                newCache[id] = ActiveJob(
                    id:          job.id,
                    name:        job.name,
                    status:      "completed",
                    conclusion:  job.conclusion ?? "success",
                    startedAt:   job.startedAt,
                    createdAt:   job.createdAt,
                    completedAt: job.completedAt ?? now,
                    htmlUrl:     job.htmlUrl,
                    isDimmed:    true
                )
            }

            // ⚠️ CALLSITE 3 of 3 — Fresh done: jobs with a conclusion inside active runs.
            // Overwrite cache entry with real conclusion data from the API.
            for job in freshDone {
                newCache[job.id] = ActiveJob(
                    id:          job.id,
                    name:        job.name,
                    status:      "completed",
                    conclusion:  job.conclusion,
                    startedAt:   job.startedAt,
                    createdAt:   job.createdAt,
                    completedAt: job.completedAt ?? now,
                    htmlUrl:     job.htmlUrl,
                    isDimmed:    true
                )
            }

            // Trim to newest 3 to cap memory usage.
            if newCache.count > 3 {
                let sorted = newCache.values
                    .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                newCache = Dictionary(
                    uniqueKeysWithValues: sorted.prefix(3).map { ($0.id, $0) }
                )
            }

            let newPrevLive = Dictionary(uniqueKeysWithValues: liveJobs.map { ($0.id, $0) })

            // Display order: in_progress → queued → done (newest first), max 3 total.
            // Priority ensures actively-running jobs are always shown first;
            // queued jobs surface next; completed jobs fill remaining slots.
            let inProgress = liveJobs.filter { $0.status == "in_progress" }
            let queued     = liveJobs.filter { $0.status == "queued" }
            let cached     = newCache.values
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

            var display: [ActiveJob] = []
            for job in inProgress where display.count < 3 { display.append(job) }
            for job in queued     where display.count < 3 { display.append(job) }
            for job in cached     where display.count < 3 { display.append(job) }

            log("RunnerStore › \(inProgress.count) in_progress \(queued.count) queued | " +
                "cache: \(newCache.count) | display: \(display.count)")

            // ── Fetch actions (workflow runs with their jobs)
            // snapPrevRuns / snapRunCache were captured on the main thread above.
            var allFetchedRuns: [ActionRun] = []
            for scope in ScopeStore.shared.scopes {
                allFetchedRuns.append(contentsOf: fetchActions(for: scope))
            }

            let liveRuns   = allFetchedRuns.filter { $0.conclusion == nil }
            let doneRuns   = allFetchedRuns.filter { $0.conclusion != nil }
            let liveRunIDs = Set(liveRuns.map { $0.id })
            let nowRuns    = Date()

            var newRunCache = snapRunCache

            // Vanished runs: were live last poll, absent now — freeze with isDimmed.
            for (id, run) in snapPrevRuns where !liveRunIDs.contains(id) {
                guard newRunCache[id] == nil else { continue }
                var frozen = run
                frozen.isDimmed = true
                if frozen.updatedAt == nil {
                    // Synthesise an updatedAt so elapsed/sort logic works.
                    frozen = ActionRun(
                        id: frozen.id, name: frozen.name, repo: frozen.repo,
                        status: "completed", conclusion: frozen.conclusion ?? "success",
                        headBranch: frozen.headBranch,
                        createdAt: frozen.createdAt, updatedAt: nowRuns,
                        htmlUrl: frozen.htmlUrl, jobs: frozen.jobs, isDimmed: true
                    )
                }
                newRunCache[id] = frozen
            }

            // Fresh-done runs: concluded while still appearing in active API results.
            for run in doneRuns {
                newRunCache[run.id] = ActionRun(
                    id: run.id, name: run.name, repo: run.repo,
                    status: "completed", conclusion: run.conclusion,
                    headBranch: run.headBranch,
                    createdAt: run.createdAt, updatedAt: run.updatedAt ?? nowRuns,
                    htmlUrl: run.htmlUrl, jobs: run.jobs, isDimmed: true
                )
            }

            // Trim to newest 5 (ci-dash.py MAX_GROUPS = 5).
            if newRunCache.count > 5 {
                let sorted = newRunCache.values
                    .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
                newRunCache = Dictionary(
                    uniqueKeysWithValues: sorted.prefix(5).map { ($0.id, $0) }
                )
            }

            let newPrevLiveRuns = Dictionary(uniqueKeysWithValues: liveRuns.map { ($0.id, $0) })

            // Display: in_progress → queued → cached done (newest first), max 5.
            let inProgressRuns = liveRuns.filter { $0.status == "in_progress" }
            let queuedRuns     = liveRuns.filter { $0.status == "queued" }
            let cachedRuns     = newRunCache.values
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }

            var displayActions: [ActionRun] = []
            for run in inProgressRuns where displayActions.count < 5 { displayActions.append(run) }
            for run in queuedRuns     where displayActions.count < 5 { displayActions.append(run) }
            for run in cachedRuns     where displayActions.count < 5 { displayActions.append(run) }

            log("RunnerStore › actions: \(inProgressRuns.count) in_progress " +
                "\(queuedRuns.count) queued | cache: \(newRunCache.count) | display: \(displayActions.count)")

            // All property writes must happen on the main thread because they are
            // observed by SwiftUI via RunnerStoreObservable (@Published properties).
            DispatchQueue.main.async {
                self.runners        = enrichedRunners
                self.jobs           = display
                self.completedCache = newCache
                self.prevLiveJobs   = newPrevLive
                self.actions        = displayActions
                self.actionCache    = newRunCache
                self.prevLiveRuns   = newPrevLiveRuns
                self.onChange?()
            }
        }
    }
}
