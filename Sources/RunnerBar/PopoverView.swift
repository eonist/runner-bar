import AppKit
import SwiftUI
import ServiceManagement

// ============================================================
// ⚠️⚠️⚠️  STOP. READ THIS ENTIRE COMMENT BEFORE TOUCHING THIS FILE.  ⚠️⚠️⚠️
// ============================================================
// VERSION: v2.1 (keep in sync with AppDelegate.swift)
//
// This file defines the root SwiftUI view inside an NSPopover.
// The sizing relationship between SwiftUI and NSPopover is extremely
// fragile. The left-jump bug was introduced and re-introduced 30+
// times before all root causes were identified.
//
// READ AppDelegate.swift SECTION 1 for the full explanation of WHY
// NSPopover behaves this way. This comment covers the SwiftUI side.
//
// ============================================================
// SECTION 1: THE FRAME CONTRACT (all rules must hold simultaneously)
// ============================================================
//
// RULE 1: The root Group MUST use .frame(idealWidth: 340, minHeight: 480)
//
//   NSHostingController with sizingOptions=.preferredContentSize reads
//   the SwiftUI layout engine's IDEAL size (not min, not max, not the
//   resolved layout size) to compute preferredContentSize.
//
//   .frame(idealWidth: 340)  => ideal width = 340  ✔ CORRECT
//   .frame(width: 340)       => layout width = 340, ideal width = BROKEN
//
//   minHeight: 480 is REQUIRED (CAUSE 8 fix).
//   Without it, the root Group reports different ideal heights per nav state:
//     .jobList  => height = content height (e.g. 240pt when few jobs)
//     .jobSteps => height = 480pt (pinned by JobStepsView's frame)
//   The height change fires preferredContentSize update => NSPopover re-anchors
//   => left jump on EVERY navigation from jobList to steps.
//   minHeight: 480 on the root Group prevents the height from ever going
//   below 480pt, matching all child nav views. No height delta => no re-anchor.
//
//   DO NOT REMOVE minHeight: 480.
//   DO NOT CHANGE .frame(idealWidth: 340) TO .frame(width: 340).
//
// RULE 2: The root Group MUST be the outermost container
//
//   The .frame(idealWidth: 340, minHeight: 480) modifier must be on the
//   direct parent of the switch statement.
//
// RULE 3: The jobList nav state MUST use fixedSize + maxHeight, NOT height
//
//   .fixedSize(horizontal: false, vertical: true) tells SwiftUI to use
//   the view's natural (ideal) vertical size rather than expanding to fill.
//   .frame(maxHeight: 480) caps the height at 480pt for long lists.
//   DO NOT wrap jobListView in a ScrollView.
//
// RULE 4: ALL child nav views MUST use maxWidth, NOT width
//
//   JobStepsView, MatrixGroupView all use:
//     .frame(maxWidth: .infinity, minHeight: 480, maxHeight: 480)
//   They MUST NEVER use .frame(width: 340, ...).
//
// ============================================================
// SECTION 2: NAVIGATION CONTRACT
// ============================================================
//
// Navigation is implemented as a @State NavState enum + Group + switch.
//
//   ✘ NavigationStack / NavigationView => fights NSHostingController sizing
//   ✘ ZStack with .opacity or .transition => measures all children at once
//   ✘ ZStack with .transition(.move) => collapses to zero width, plays from left edge
//   ✔ Group + switch (current approach) => measures exactly one child at a time
//
// DO NOT add .transition() to any case in the switch statement.
//
// ============================================================
// SECTION 3: SYMPTOMS AND CAUSES
// ============================================================
//
// Symptom A — Popover flies to far left on open:
//   Cause: preferredContentSize.width is wrong. .frame(width:) not idealWidth.
//
// Symptom B — Popover jumps left when navigating to steps/matrix view:
//   Cause: child view reports different ideal width than 340.
//
// Symptom C — Popover jumps left every ~10 seconds while open:
//   Cause: observable.reload() called while popover is open. CAUSE 2.
//
// Symptom D — Popover opens and immediately closes:
//   Cause: objectWillChange pending at show(). CAUSE 3 or CAUSE 6.
//
// Symptom E — Large empty space below content when no jobs:
//   Cause: .frame(height:480) instead of .fixedSize+.frame(maxHeight:480).
//
// Symptom F — Popover jumps only on first open:
//   Cause: popoverIsOpen set after reload() in togglePopover. CAUSE 4.
//
// Symptom G — Popover jumps ~2 seconds after navigating to steps view:
//   Cause: async step load fires @State change after appear. CAUSE 7.
//
// Symptom H — Popover jumps immediately when tapping any job row:
//   Cause: root Group has no minHeight. Height changes from jobList (short)
//   to jobSteps (480pt) on navigation. CAUSE 8. Fix: minHeight:480 on root.
//
// ============================================================

// MARK: - Navigation state

private enum NavState: Equatable {
    case jobList
    case jobSteps(job: ActiveJob, steps: [JobStep], scope: String)
    case matrixGroup(baseName: String, jobs: [ActiveJob], scope: String)

    static func == (lhs: NavState, rhs: NavState) -> Bool {
        switch (lhs, rhs) {
        case (.jobList, .jobList): return true
        case (.jobSteps(let a, _, _), .jobSteps(let b, _, _)): return a.id == b.id
        case (.matrixGroup(let a, _, _), .matrixGroup(let b, _, _)): return a == b
        default: return false
        }
    }
}

// MARK: - Root view

struct PopoverView: View {
    @ObservedObject var store: RunnerStoreObservable
    @State private var newScope = ""
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var isAuthenticated = (githubToken() != nil)
    @State private var tick = 0
    @State private var navState: NavState = .jobList

    var body: some View {
        Group {
            switch navState {

            case .jobList:
                jobListView
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: 480, alignment: .top)

            case .jobSteps(let job, let steps, let scope):
                JobStepsView(
                    job: job,
                    steps: steps,
                    scope: scope,
                    onBack: { navState = .jobList }
                )

            case .matrixGroup(let baseName, let jobs, let scope):
                MatrixGroupView(
                    baseName: baseName,
                    jobs: jobs,
                    scope: scope,
                    onBack: { navState = .jobList }
                )
            }
        }
        // ⚠️⚠️⚠️  BOTH PARAMETERS ARE MANDATORY.  ⚠️⚠️⚠️
        //
        // idealWidth: 340 — locks preferredContentSize.width = 340 across
        //   all nav states. DO NOT change to width: 340.
        //
        // minHeight: 480 — CAUSE 8 FIX. Prevents height from being shorter
        //   than 480pt in the jobList state (which has dynamic height).
        //   Without this, navigating jobList→jobSteps changes ideal height
        //   from e.g. 240pt to 480pt => preferredContentSize update =>
        //   NSPopover re-anchors => left jump on every tap.
        //   All child nav views already pin to minHeight:480 on their own
        //   body frame. This root frame ensures jobList matches them.
        //
        // DO NOT REMOVE EITHER PARAMETER.
        // DO NOT ADD maxHeight here — jobList controls its own max via .frame(maxHeight:480).
        .frame(idealWidth: 340, minHeight: 480)
        .onReceive(store.objectWillChange) {
            isAuthenticated = (githubToken() != nil)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick += 1 }
        }
    }

    // MARK: - Job list view
    private var jobListView: some View {
        VStack(alignment: .leading, spacing: 0) {

            HStack {
                Text("RunnerBar v2.0")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                if isAuthenticated {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("Authenticated")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button(action: signInWithGitHub) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 8, height: 8)
                            Text("Sign in with GitHub")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            Text("Active Jobs")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 2)

            if store.state.jobs.isEmpty {
                Text("No active jobs")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .padding(.bottom, 2)
            } else {
                let groups = groupJobs(Array(store.state.jobs.prefix(3)))
                ForEach(groups) { group in
                    groupRow(for: group)
                }
                .padding(.bottom, 6)
            }

            Divider()

            Text("Local runners")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 2)

            if store.state.runners.isEmpty {
                Text(isAuthenticated ? "No runners found" : "Authenticate to see runners")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .padding(.bottom, 2)
            } else {
                ForEach(store.state.runners, id: \.id) { runner in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(dotColor(for: runner))
                            .frame(width: 8, height: 8)
                        Text(runner.name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Spacer()
                        Text(runner.displayStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Scopes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                ForEach(ScopeStore.shared.scopes, id: \.self) { scope in
                    HStack {
                        Text(scope).font(.system(size: 12))
                        Spacer()
                        Button(action: {
                            ScopeStore.shared.remove(scope)
                            store.reload()
                        }) {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                }

                HStack {
                    TextField("owner/repo or org", text: $newScope)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit { submitScope() }
                    Button(action: submitScope) {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .disabled(newScope.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            Divider()

            Toggle(isOn: $launchAtLogin) {
                Text("Launch at login").font(.system(size: 13))
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onChange(of: launchAtLogin) { _ in LoginItem.toggle() }

            Divider()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                HStack {
                    Image(systemName: "xmark.square")
                    Text("Quit")
                }
                .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

        } // end VStack
    }

    // MARK: - Group row builder
    //
    // ⚠️ CAUSE 7 FIX: loadStepsAndNavigate fetches BEFORE navigating.
    // DO NOT change to navigate-first pattern.

    @ViewBuilder
    private func groupRow(for group: JobGroup) -> some View {
        let jobScope = ScopeStore.shared.scopes.first ?? ""

        Button(action: {
            switch group {
            case .single(let job):
                loadStepsAndNavigate(job: job, scope: jobScope)
            case .matrix(let baseName, let jobs):
                navState = .matrixGroup(baseName: baseName, jobs: jobs, scope: jobScope)
            }
        }) {
            HStack(spacing: 8) {
                groupDot(for: group)

                Text(group.displayName)
                    .font(.system(size: 12))
                    .foregroundColor(group.isDimmed ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if group.isDimmed {
                    Text(conclusionLabel(conclusion: group.conclusion))
                        .font(.caption)
                        .foregroundColor(conclusionColor(conclusion: group.conclusion))
                        .frame(width: 76, alignment: .trailing)
                } else {
                    Text(statusLabel(status: group.status))
                        .font(.caption)
                        .foregroundColor(statusColor(status: group.status))
                        .frame(width: 76, alignment: .trailing)
                }

                Text(group.isDimmed ? group.elapsed : liveElapsed(group: group))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // ⚠️ CAUSE 7 FIX: fetch steps BEFORE navigating.
    private func loadStepsAndNavigate(job: ActiveJob, scope: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let steps = fetchJobSteps(jobID: job.id, scope: scope)
            DispatchQueue.main.async {
                navState = .jobSteps(job: job, steps: steps, scope: scope)
            }
        }
    }

    // MARK: - Elapsed
    private func liveElapsed(group: JobGroup) -> String { _ = tick; return group.elapsed }

    // MARK: - Dot helpers
    @ViewBuilder
    private func groupDot(for group: JobGroup) -> some View {
        if case .matrix = group {
            ZStack {
                Circle().fill(groupDotColor(for: group)).frame(width: 6, height: 6).offset(x: -2)
                Circle().fill(groupDotColor(for: group).opacity(0.6)).frame(width: 6, height: 6).offset(x: 2)
            }
            .frame(width: 7, height: 7)
        } else {
            Circle().fill(groupDotColor(for: group)).frame(width: 7, height: 7)
        }
    }

    private func groupDotColor(for group: JobGroup) -> Color {
        if group.isDimmed { return group.conclusion == "failure" ? .red : .secondary }
        switch group.status {
        case "in_progress": return .yellow
        case "queued":      return .gray
        default:            return .secondary
        }
    }

    // MARK: - Label helpers
    private func statusLabel(status: String) -> String {
        switch status {
        case "in_progress": return "In Progress"
        case "queued":      return "Queued"
        default:            return "Done"
        }
    }
    private func statusColor(status: String) -> Color { status == "in_progress" ? .yellow : .secondary }

    private func conclusionLabel(conclusion: String?) -> String {
        switch conclusion {
        case "success":   return "✓ success"
        case "failure":   return "✗ failure"
        case "cancelled": return "⊖ cancelled"
        case "skipped":   return "− skipped"
        default:          return conclusion ?? "done"
        }
    }
    private func conclusionColor(conclusion: String?) -> Color {
        switch conclusion {
        case "success": return .green
        case "failure": return .red
        default:        return .secondary
        }
    }

    // MARK: - Runner helpers
    private func dotColor(for runner: Runner) -> Color {
        if runner.status != "online" { return .gray }
        return runner.busy ? .yellow : .green
    }

    // MARK: - Actions
    private func signInWithGitHub() {
        let script = "tell application \"Terminal\" to do script \"gh auth login\""
        NSAppleScript(source: script)?.executeAndReturnError(nil)
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }

    private func submitScope() {
        let trimmed = newScope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ScopeStore.shared.add(trimmed)
        RunnerStore.shared.start()
        store.reload()
        newScope = ""
    }
}

// MARK: - Observable

struct StoreState {
    var runners: [Runner]   = []
    var jobs: [ActiveJob]   = []
}

final class RunnerStoreObservable: ObservableObject {
    @Published var state: StoreState = StoreState()

    init() {
        state = StoreState(
            runners: RunnerStore.shared.runners,
            jobs:    RunnerStore.shared.jobs
        )
    }

    func reload() {
        state = StoreState(
            runners: RunnerStore.shared.runners,
            jobs:    RunnerStore.shared.jobs
        )
    }
}
