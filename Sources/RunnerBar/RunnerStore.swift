import Foundation
import AppKit

final class RunnerStore {
    static let shared = RunnerStore()

    private(set) var runners: [Runner] = []
    private var timer: Timer?
    var onChange: (() -> Void)?

    func start() {
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    func fetch() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            var all: [Runner] = []
            for scope in ScopeStore.shared.scopes {
                all.append(contentsOf: fetchRunners(for: scope))
            }
            DispatchQueue.main.async {
                self.runners = all
                self.onChange?()
            }
        }
    }
}
