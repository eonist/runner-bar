import Foundation
import AppKit

enum AggregateStatus {
    case allOnline
    case someOffline
    case allOffline

    var dot: String {
        switch self {
        case .allOnline:  return "🟢"
        case .someOffline: return "🟡"
        case .allOffline: return "⚫"
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
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    func fetch() {
        log("RunnerStore › fetch — \(ScopeStore.shared.scopes.count) scope(s)")
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            var all: [Runner] = []
            for scope in ScopeStore.shared.scopes {
                log("RunnerStore › fetching scope: \(scope)")
                let fetched = fetchRunners(for: scope)
                log("RunnerStore › scope \(scope) → \(fetched.count) runner(s)")
                all.append(contentsOf: fetched)
            }
            let busyCount = max(all.filter { $0.busy }.count, 1)
            let enriched = all.map { runner -> Runner in
                var r = runner
                r.busyCount = busyCount
                return r
            }
            log("RunnerStore › fetch complete — \(enriched.count) total runner(s), busyCount=\(busyCount)")
            DispatchQueue.main.async {
                self.runners = enriched
                self.onChange?()
            }
        }
    }
}
