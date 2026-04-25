import SwiftUI

// ============================================================
// ⚠️⚠️⚠️  STOP. READ THIS ENTIRE COMMENT BEFORE TOUCHING THIS FILE.  ⚠️⚠️⚠️
// ============================================================
// VERSION: v2.0 (keep in sync with AppDelegate.swift)
//
// This view is rendered inside PopoverView's root Group as the
// .jobSteps navigation state. It exists inside an NSPopover whose
// sizing is extremely fragile. Read PopoverView.swift SECTION 1
// and AppDelegate.swift SECTION 1 before making any changes.
//
// ============================================================
// THE ONLY FRAME RULE YOU NEED TO KNOW FOR THIS FILE
// ============================================================
//
// The body of this view MUST end with:
//   .frame(maxWidth: .infinity, minHeight: 480, maxHeight: 480)
//
// WHY maxWidth: .infinity and NOT width: 340:
//   PopoverView's root Group has .frame(idealWidth: 340).
//   NSHostingController reads the SwiftUI ideal size to set
//   preferredContentSize. .frame(idealWidth: 340) on the root
//   Group establishes 340pt as the ideal width for the entire tree.
//
//   If THIS view uses .frame(width: 340), it sets a LAYOUT constraint
//   of 340pt. This fights the parent's idealWidth:340 and causes the
//   ideal width to be reported inconsistently across navigation states.
//   The result: preferredContentSize.width changes when navigating
//   to/from this view => NSPopover re-anchors its full screen position
//   => popover jumps to the far left of the screen.
//
//   .frame(maxWidth: .infinity) expands to fill the space established
//   by the parent's idealWidth constraint without fighting it.
//   This keeps ideal width = 340 at all times.
//
// WHY minHeight: 480, maxHeight: 480:
//   Pins the height to exactly 480pt for this navigation state.
//   This matches the maxHeight:480 cap on the jobList state.
//   DO NOT remove minHeight — without it, short step lists shrink
//   the popover height, causing a re-anchor => left jump.
//
// ✘ DO NOT change to: .frame(width: 340, height: 480)
// ✘ DO NOT change to: .frame(width: 340, minHeight: 480, maxHeight: 480)
// ✘ DO NOT change to: .frame(maxWidth: 340, ...)
// ✔ KEEP AS:          .frame(maxWidth: .infinity, minHeight: 480, maxHeight: 480)
//
// ============================================================
// CAUSE 7 — WHY THIS VIEW NO LONGER LOADS DATA ITSELF
// ============================================================
//
// In v1.7-v1.9, this view called loadSteps() in .onAppear, which
// fired a background fetch and landed the result ~2 seconds later via:
//   steps = result      => @State change
//   isLoading = false   => @State change
//
// These @State changes triggered SwiftUI re-renders WHILE the popover
// was open. Even though the outer frame is fixed at 480pt, the content
// change (spinner => step list) caused SwiftUI to recalculate the
// ideal size, which NSHostingController picked up via preferredContentSize,
// which caused NSPopover to re-anchor => left jump 2 seconds after opening.
//
// THE FIX (v2.0):
//   Steps are now fetched in PopoverView.groupRow BEFORE navigating.
//   The navState is set to .jobSteps(job:steps:scope:) only AFTER the
//   fetch completes. This view receives steps as an init parameter and
//   renders immediately without any async loading.
//
//   NO async load in this view = NO @State changes after appear
//   = NO re-renders after appear = NO preferredContentSize change
//   = NO left jump.
//
// ⚠️ DO NOT re-add loadSteps() or any async data loading to this view.
// ⚠️ DO NOT add isLoading @State here. Steps must arrive pre-loaded.
// ⚠️ If you need to refresh steps while the view is displayed, use a
//    Timer that only updates TEXT (elapsed times), not the steps array.
//    Changing the steps array = @State change = re-render = possible jump.
//
// ============================================================
// NAVIGATION CONTRACT FOR THIS VIEW
// ============================================================
//
// This view has its own internal navigation: stepsListView <-> StepLogView.
// That internal navigation follows the same rules:
//
//   ✘ DO NOT use ZStack + .transition(.move(edge:))
//      In NSPopover context, ZStack collapses to zero width during the
//      transition and the move animation plays from the LEFT EDGE OF THE
//      SCREEN, not from within the popover. This looks exactly like the
//      left-jump bug and is just as bad.
//
//   ✔ USE Group + if/else (current approach)
//      Group with plain if/else swaps content in-place with no transitions
//      and no size artifacts.
//
// ============================================================

struct JobStepsView: View {
    let job: ActiveJob
    // ⚠️ steps is passed in PRE-LOADED from PopoverView.groupRow.
    // DO NOT make this @State. DO NOT fetch inside this view.
    // See CAUSE 7 comment above.
    let steps: [JobStep]
    let scope: String
    let onBack: () -> Void

    @State private var tick = 0
    @State private var selectedStep: JobStep? = nil

    var body: some View {
        // ⚠️ Group + if/else for internal navigation. See NAVIGATION CONTRACT above.
        // DO NOT replace with ZStack + transitions.
        Group {
            if let step = selectedStep {
                StepLogView(
                    job: job,
                    step: step,
                    scope: scope,
                    onBack: { selectedStep = nil }
                )
            } else {
                stepsListView
            }
        }
        // ⚠️ THIS FRAME IS MANDATORY. See frame contract at top of file.
        // maxWidth:.infinity — DO NOT change to width:340
        // minHeight:480 — DO NOT remove (prevents shrink on short lists)
        // maxHeight:480 — DO NOT remove (prevents expand on tall lists)
        .frame(maxWidth: .infinity, minHeight: 480, maxHeight: 480)
    }

    // MARK: - Steps list

    private var stepsListView: some View {
        // ⚠️ ScrollView is correct here (unlike jobListView which must NOT use ScrollView).
        // The outer .frame(maxHeight:480) clamps the scroll region to 480pt.
        // The ScrollView itself does not affect preferredContentSize because it
        // is inside the clamping frame, not measuring the outer container.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // Header
                HStack(spacing: 6) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)

                    Text(job.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()

                if steps.isEmpty {
                    Text("No steps found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                } else {
                    ForEach(steps) { step in
                        let tappable = step.status == "completed"
                        Button(action: {
                            guard tappable else { return }
                            selectedStep = step
                        }) {
                            HStack(spacing: 8) {
                                stepDot(for: step)

                                Text(step.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(step.isDimmed ? .secondary : .primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Spacer()

                                if step.status == "completed" {
                                    Text(conclusionLabel(for: step))
                                        .font(.caption)
                                        .foregroundColor(conclusionColor(for: step))
                                        .frame(width: 76, alignment: .trailing)
                                } else {
                                    Text(statusLabel(for: step))
                                        .font(.caption)
                                        .foregroundColor(statusColor(for: step))
                                        .frame(width: 76, alignment: .trailing)
                                }

                                Text(liveElapsed(for: step))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9))
                                    .foregroundColor(tappable ? .secondary.opacity(0.5) : .clear)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(step.isDimmed ? 0.6 : 1.0)
                    }
                    .padding(.bottom, 6)
                }

            } // end VStack
        } // end ScrollView
        .onAppear {
            // ⚠️ tick drives liveElapsed() label updates only.
            // It does NOT change the steps array or any structural content.
            // Text label updates do NOT change the view's ideal size.
            // It is safe to tick while the popover is open.
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick += 1 }
        }
    }

    // MARK: - Helpers
    private func liveElapsed(for step: JobStep) -> String { _ = tick; return step.elapsed }

    @ViewBuilder
    private func stepDot(for step: JobStep) -> some View {
        Circle().fill(dotColor(for: step)).frame(width: 7, height: 7)
    }

    private func dotColor(for step: JobStep) -> Color {
        switch step.status {
        case "in_progress": return .yellow
        case "completed":
            switch step.conclusion {
            case "success": return .green
            case "failure": return .red
            default:        return .secondary
            }
        default: return .gray
        }
    }

    private func statusLabel(for step: JobStep) -> String {
        step.status == "in_progress" ? "In Progress" : "Queued"
    }
    private func statusColor(for step: JobStep) -> Color {
        step.status == "in_progress" ? .yellow : .secondary
    }
    private func conclusionLabel(for step: JobStep) -> String {
        switch step.conclusion {
        case "success":   return "✓ success"
        case "failure":   return "✗ failure"
        case "skipped":   return "− skipped"
        case "cancelled": return "⊖ cancelled"
        default:          return step.conclusion ?? "done"
        }
    }
    private func conclusionColor(for step: JobStep) -> Color {
        switch step.conclusion {
        case "success": return .green
        case "failure": return .red
        default:        return .secondary
        }
    }
}
