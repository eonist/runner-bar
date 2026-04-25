import SwiftUI

// ============================================================
// ⚠️⚠️⚠️  STOP. READ THIS ENTIRE COMMENT BEFORE TOUCHING THIS FILE.  ⚠️⚠️⚠️
// ============================================================
// VERSION: v2.3 (keep in sync with AppDelegate.swift)
//
// This view is rendered inside PopoverView's root Group as the
// .matrixGroup navigation state. It exists inside an NSPopover
// whose sizing is brutally fragile. The left-jump bug was introduced
// 30+ times in a single day on this project.
//
// Read AppDelegate.swift SECTION 1 and PopoverView.swift SECTION 1
// before making ANY change to this file.
//
// ============================================================
// SECTION 1 — FRAME CONTRACT
// ============================================================
//
// The body Group MUST end with:
//   .frame(maxWidth: .infinity, minHeight: 480, maxHeight: 480)
//
//   ✘ DO NOT change to: .frame(width: 340, height: 480)
//   ✘ DO NOT change to: .frame(width: 340, minHeight: 480, maxHeight: 480)
//   ✘ DO NOT change to: .frame(maxWidth: 340, ...)
//   ✔ KEEP AS:          .frame(maxWidth: .infinity, minHeight: 480, maxHeight: 480)
//
// ============================================================
// SECTION 2 — NAVIGATION CONTRACT
// ============================================================
//
// Both navigation levels MUST use Group + if/else.
// DO NOT use ZStack + .transition(.move(edge:)).
// ZStack + move transitions collapse width to zero during animation
// and play from the left screen edge. Catastrophic. Do not retry.
//
// ============================================================
// SECTION 3 — WHY STEPS ARE PRE-LOADED HERE (CAUSE 7)
// ============================================================
//
// JobStepsView requires steps passed as init parameter (pre-loaded).
// loadAndNavigate() fetches BEFORE setting selectedJob.
// DO NOT navigate first and fetch inside JobStepsView.
//
// ============================================================
// SECTION 4 — FREE FUNCTION, NOT A STATIC METHOD
// ============================================================
//
//   ✔ CORRECT:   fetchJobSteps(jobID: job.id, scope: scope)
//   ✘ INCORRECT: JobStep.fetchJobSteps(...)  ← compile error
//
// ============================================================
// SECTION 5 — DOT/SPINNER: ZStack+OPACITY, NOT Group+if/else
// ============================================================
//
// The dot column uses ZStack with .opacity(0/1) to switch between
// the Circle dot and the ProgressView spinner.
//
// WHY NOT Group { if isLoadingJob != nil { ProgressView() } else { Circle() } }:
//   A structural if/else inside the view tree causes SwiftUI to
//   INSERT and REMOVE views on the first tap (when isLoadingJob
//   transitions nil => job). That insertion/removal is a structural
//   re-render. SwiftUI recalculates the ideal size of the entire row.
//   NSHostingController picks up the new preferredContentSize.
//   NSPopover re-anchors => left jump. Symptom: jump on first tap only.
//
// WHY ZStack + .opacity works:
//   Both Circle and ProgressView are ALWAYS in the view tree.
//   .opacity(0) hides a view without removing it from layout.
//   The ideal size calculation never changes — the ZStack always
//   contains both children. No structural re-render => no size change
//   => no re-anchor => no jump.
//
// ⚠️ DO NOT replace the ZStack+opacity pattern with Group+if/else.
// ⚠️ DO NOT use .hidden() — it removes from layout (same problem).
// ⚠️ DO NOT use .transition() on either child — same problem.
//
// ============================================================
// SECTION 6 — ROW ALIGNMENT CONTRACT
// ============================================================
//
// Every row: [dot ZStack: 16pt] [name: flexible] [status: 76pt] [elapsed: 40pt] [chevron]
// ⚠️ DO NOT reduce dot container from 16pt.
// ⚠️ DO NOT change status column from 76pt.
// ⚠️ DO NOT change elapsed column from 40pt.
//
// ============================================================
// SECTION 7 — PRE-COMMIT CHECKLIST
// ============================================================
//
//   [ ] body Group ends with .frame(maxWidth:.infinity, minHeight:480, maxHeight:480)
//   [ ] No .frame(width:340) anywhere
//   [ ] Navigation uses Group + if/else, not ZStack + transitions
//   [ ] Dot column uses ZStack+opacity, NOT Group+if/else or @ViewBuilder if/else
//   [ ] loadAndNavigate() fetches BEFORE setting selectedJob
//   [ ] fetchJobSteps called as free function
//   [ ] Version bumped if logic changed
//
// ============================================================

struct MatrixGroupView: View {
    let baseName: String
    let jobs: [ActiveJob]
    let scope: String
    let onBack: () -> Void

    @State private var selectedJob: ActiveJob? = nil
    @State private var selectedSteps: [JobStep] = []
    @State private var isLoadingJob: ActiveJob? = nil
    @State private var tick = 0

    var body: some View {
        // ⚠️ Group + if/else for navigation. NOT ZStack + transitions. See SECTION 2.
        Group {
            if let job = selectedJob {
                JobStepsView(
                    job: job,
                    steps: selectedSteps,
                    scope: scope,
                    onBack: {
                        selectedJob = nil
                        selectedSteps = []
                    }
                )
            } else {
                variantListView
            }
        }
        // ⚠️ MANDATORY. See SECTION 1.
        .frame(maxWidth: .infinity, minHeight: 480, maxHeight: 480)
    }

    // MARK: - Variant list

    private var variantListView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                HStack(spacing: 6) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)

                    Text(baseName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Text("\(jobs.count) variants")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()

                ForEach(jobs) { job in
                    variantRow(for: job)
                }
                .padding(.bottom, 6)

            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick += 1 }
        }
    }

    // MARK: - Variant row

    @ViewBuilder
    private func variantRow(for job: ActiveJob) -> some View {
        let isLoading = isLoadingJob?.id == job.id
        Button(action: { loadAndNavigate(to: job) }) {
            HStack(alignment: .center, spacing: 8) {

                // ⚠️ ZStack+opacity. DO NOT change to Group+if/else.
                // See SECTION 5. Structural if/else causes a re-render on
                // first tap that changes preferredContentSize => left jump.
                ZStack {
                    Circle()
                        .fill(dotColor(for: job))
                        .frame(width: 7, height: 7)
                        .opacity(isLoading ? 0 : 1)
                    ProgressView()
                        .scaleEffect(0.6)
                        .opacity(isLoading ? 1 : 0)
                }
                .frame(width: 16, height: 16)

                Text(job.matrixVariant ?? job.name)
                    .font(.system(size: 12))
                    .foregroundColor(job.isDimmed ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if job.isDimmed {
                    Text(conclusionLabel(for: job))
                        .font(.caption)
                        .foregroundColor(conclusionColor(for: job))
                        .frame(width: 76, alignment: .trailing)
                } else {
                    Text(statusLabel(for: job))
                        .font(.caption)
                        .foregroundColor(statusColor(for: job))
                        .frame(width: 76, alignment: .trailing)
                }

                Text(liveElapsed(for: job))
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
        .opacity(job.isDimmed ? 0.7 : 1.0)
        .disabled(isLoadingJob != nil)
    }

    // MARK: - Pre-load steps then navigate
    //
    // ⚠️ CAUSE 7 FIX: fetch THEN navigate. DO NOT flip order. See SECTION 3.

    private func loadAndNavigate(to job: ActiveJob) {
        guard isLoadingJob == nil else { return }
        isLoadingJob = job
        Task {
            let steps = fetchJobSteps(jobID: job.id, scope: scope)
            await MainActor.run {
                selectedSteps = steps
                selectedJob = job
                isLoadingJob = nil
            }
        }
    }

    // MARK: - Helpers
    private func liveElapsed(for job: ActiveJob) -> String { _ = tick; return job.elapsed }

    private func dotColor(for job: ActiveJob) -> Color {
        if job.isDimmed { return job.conclusion == "failure" ? .red : .secondary }
        switch job.status {
        case "in_progress": return .yellow
        case "queued":      return .gray
        default:            return .secondary
        }
    }
    private func statusLabel(for job: ActiveJob) -> String {
        job.status == "in_progress" ? "In Progress" : "Queued"
    }
    private func statusColor(for job: ActiveJob) -> Color {
        job.status == "in_progress" ? .yellow : .secondary
    }
    private func conclusionLabel(for job: ActiveJob) -> String {
        switch job.conclusion {
        case "success":   return "✓ success"
        case "failure":   return "✗ failure"
        case "cancelled": return "⊖ cancelled"
        case "skipped":   return "− skipped"
        default:          return job.conclusion ?? "done"
        }
    }
    private func conclusionColor(for job: ActiveJob) -> Color {
        switch job.conclusion {
        case "success": return .green
        case "failure": return .red
        default:        return .secondary
        }
    }
}
