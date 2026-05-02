import AppKit
import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// ⚠️ REGRESSION GUARD — mirrors JobDetailView contract (ref #52 #54 #57)
// ═══════════════════════════════════════════════════════════════════════════════
//
// ── FRAME CONTRACT ────────────────────────────────────────────────────────────
//   This view receives the same FIXED frame from AppDelegate as JobDetailView.
//   Frame is sized once at openPopover() from mainView()'s fittingSize; it never
//   changes while the popover is open. ScrollView absorbs overflow — same as
//   JobDetailView.
//
// ── LAYOUT RULES ──────────────────────────────────────────────────────────────
//   ✔ Root: .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
//   ✔ Job list MUST be inside ScrollView (may overflow frame)
//   ✔ Header (back button + run name + Divider) MUST be OUTSIDE ScrollView
//   ❌ NEVER put header inside ScrollView — back button becomes inaccessible
//   ❌ NEVER add .idealWidth to root frame
//   ❌ NEVER add .frame(height:) to root
//   ❌ NEVER call navigate() directly from here — use onBack / onSelectJob callbacks
// ═══════════════════════════════════════════════════════════════════════════════

/// Navigation level 2 (Actions path): shows the jobs inside a workflow run.
///
/// Drill-down chain:
///   PopoverMainView (action row tap)
///   → ActionDetailView          ← this view
///   → JobDetailView (step list)  ← existing, unchanged
///   → StepLogView (log)          ← existing, unchanged
struct ActionDetailView: View {
    let run: ActionRun
    let onBack: () -> Void

    // onSelectJob: called when user taps a job row.
    // AppDelegate wires this to navigate(to: detailView(job:)).
    let onSelectJob: (ActiveJob) -> Void

    // tick drives the live elapsed timer in the header.
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header: OUTSIDE ScrollView — always visible at top
            HStack(spacing: 6) {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.caption)
                        Text("Actions").font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()  // ⚠️ load-bearing — pushes elapsed to the right edge
                Text(run.isDimmed ? run.elapsed : elapsedLive(tick: tick))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // Run name + branch below the nav bar.
            VStack(alignment: .leading, spacing: 2) {
                Text(run.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let branch = run.headBranch {
                    Text(branch)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // ── Jobs list: INSIDE ScrollView
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    if run.jobs.isEmpty {
                        Text("No jobs available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(run.jobs) { job in
                            Button(action: { onSelectJob(job) }) {
                                HStack(spacing: 8) {
                                    // Status dot mirrors the dot in PopoverMainView's job rows.
                                    Circle()
                                        .fill(jobDotColor(for: job))
                                        .frame(width: 7, height: 7)

                                    Text(job.name)
                                        .font(.system(size: 12))
                                        .foregroundColor(job.isDimmed ? .secondary : .primary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    Spacer()  // ⚠️ load-bearing

                                    // Status/conclusion label
                                    Text(job.isDimmed ? conclusionLabel(for: job) : jobStatusLabel(for: job))
                                        .font(.caption)
                                        .foregroundColor(job.isDimmed ? conclusionColor(for: job) : jobStatusColor(for: job))
                                        .frame(width: 76, alignment: .trailing)

                                    Text(job.elapsed)
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.secondary)
                                        .frame(width: 40, alignment: .trailing)

                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick += 1 }
        }
    }

    // Returns run.elapsed re-evaluated every tick for a live countdown.
    private func elapsedLive(tick _: Int) -> String { run.elapsed }

    // MARK: - Job row helpers (mirrors PopoverMainView helpers)

    private func jobDotColor(for job: ActiveJob) -> Color {
        job.isDimmed ? .secondary : (job.status == "in_progress" ? .yellow : .gray)
    }

    private func jobStatusLabel(for job: ActiveJob) -> String {
        switch job.status {
        case "in_progress": return "In Progress"
        case "queued":      return "Queued"
        default:            return "Done"
        }
    }

    private func jobStatusColor(for job: ActiveJob) -> Color {
        job.status == "in_progress" ? .yellow : .secondary
    }

    private func conclusionLabel(for job: ActiveJob) -> String {
        switch job.conclusion {
        case "success":   return "✓ success"
        case "failure":   return "✗ failure"
        case "cancelled": return "⊗ cancelled"
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
