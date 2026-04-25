import AppKit
import SwiftUI

// ⚠️ REGRESSION GUARD — frame rules (ref #52 #54 #57)
//
// ── ARCHITECTURE ──────────────────────────────────────────────────────────────
//   AppDelegate opens the popover at fittingSize of mainView() — ALWAYS.
//   navigate() swaps hc.rootView with ZERO size changes (popover is open).
//   JobDetailView receives whatever frame mainView() sized the popover to.
//   That frame may be smaller than all steps combined.
//
// ── WHY v0.22–v0.28 ALL HAD THE CENTERING BUG ────────────────────────────────
//   Every attempt tried to make the frame taller to fit the steps.
//   That requires either:
//     a) Resizing in navigate() — FORBIDDEN (popover open = left-jump)
//     b) Resizing in onChange  — FORBIDDEN (popover may be open = left-jump)
//     c) preferredContentSize  — FORBIDDEN (re-anchors on every rootView swap)
//     d) Hard-coded large height — breaks main view height
//   All four introduce regressions.
//
// ── THE CORRECT FIX (v0.29+) ─────────────────────────────────────────────────
//   Don't fight the frame — work within it.
//   Header (back button + job name) stays fixed at the top, always visible.
//   Steps list is wrapped in a ScrollView — scrolls within the available frame.
//   The view ALWAYS fits whatever frame AppDelegate gives it, regardless of
//   step count. Zero changes to AppDelegate, navigate(), onChange, sizingOptions.
//
// ── RULES ─────────────────────────────────────────────────────────────────────
//   ✔ Steps list MUST stay inside ScrollView — may be taller than available frame
//   ✔ Header (HStack + Text + Divider) MUST stay outside ScrollView — always visible
//   ✔ Root: .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
//   ❌ NEVER put header inside ScrollView — back button becomes inaccessible
//   ❌ NEVER remove ScrollView — centering bug returns for jobs with many steps
//   ❌ NEVER add idealWidth to root — only meaningful under preferredContentSize (FORBIDDEN)
//   ❌ NEVER add .frame(height:) to root — fights AppDelegate's fixed frame
//   ❌ NEVER add .fixedSize() to root — collapses view
//   ❌ NEVER resize in navigate() — popover is open = left-jump (#52 #54)
struct JobDetailView: View {
    let job: ActiveJob
    let onBack: () -> Void
    // Called when user taps a step row — navigates to StepLogView
    let onSelectStep: (JobStep) -> Void
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header: OUTSIDE ScrollView — always visible at top
            // ⚠️ Spacer() is load-bearing — do NOT remove
            HStack(spacing: 6) {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.caption)
                        Text("Jobs").font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()  // ⚠️ load-bearing — do NOT remove
                Text(job.isDimmed ? job.elapsed : elapsedLive(tick: tick))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            Text(job.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Divider()

            // ── Steps: INSIDE ScrollView
            // ⚠️ ScrollView is REQUIRED. See regression guard above.
            // Tapping a step calls onSelectStep(step) → AppDelegate.navigate() to StepLogView.
            // ⚠️ DO NOT use NSWorkspace.open() here — spec requires in-app log view.
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    if job.steps.isEmpty {
                        Text("No step data available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(job.steps) { step in
                            Button(action: { onSelectStep(step) }) {
                                HStack(spacing: 8) {
                                    Text(step.conclusionIcon)
                                        .font(.system(size: 11))
                                        .foregroundColor(stepColor(step))
                                        .frame(width: 14, alignment: .center)
                                    Text(step.name)
                                        .font(.system(size: 12))
                                        .foregroundColor(step.status == "queued" ? .secondary : .primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()  // load-bearing — do NOT remove
                                    Text(step.elapsed)
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.secondary)
                                        .frame(width: 40, alignment: .trailing)
                                    // Chevron indicates drill-down to log view
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
        // ⚠️ Fill AppDelegate's fixed frame. Pin to top.
        // ScrollView ensures steps never overflow regardless of count.
        // ❌ NEVER add idealWidth — not meaningful in current fittingSize architecture
        // ❌ NEVER add .frame(height:) — fights AppDelegate's fixed frame
        // ❌ NEVER add .fixedSize() — collapses the view
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick += 1 }
        }
    }

    private func elapsedLive(tick _: Int) -> String { job.elapsed }

    private func stepColor(_ step: JobStep) -> Color {
        switch step.conclusion {
        case "success":  return .green
        case "failure":  return .red
        default:         return step.status == "in_progress" ? .yellow : .secondary
        }
    }
}
