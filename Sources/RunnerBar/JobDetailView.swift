import AppKit
import SwiftUI

// ⚠️ REGRESSION GUARD — READ BEFORE CHANGING ANYTHING (ref #52 #54 #57 #59)
//
// ARCHITECTURE:
//   AppDelegate uses sizingOptions=[] + manual contentSize.
//   openPopover() sets contentSize to computeMainHeight() before show().
//   navigate() swaps hc.rootView ONLY while popover IS open.
//   JobDetailView renders inside the SAME fixed frame as PopoverMainView.
//
// RULE 1 — ROOT FRAME:
//   MUST use .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
//   This fills the fixed contentSize frame AppDelegate provides.
//   ❌ NEVER use .frame(idealWidth:) — only used in preferredContentSize mode.
//   ❌ NEVER use .frame(width: 320) or .frame(height: ...) — fixed sizes fight the
//      frame AppDelegate sets and cause center-alignment or clipping.
//   ❌ NEVER use .fixedSize() — collapses the view to intrinsic size, losing fill.
//
// RULE 2 — NO SIZE CHANGES IN navigate():
//   navigate() fires while the popover IS open (user tapped a row inside it).
//   Any contentSize change while popover is open = NSPopover re-anchors = LEFT-JUMP.
//   The Spacer(minLength: 8) at bottom absorbs remaining vertical space gracefully.
//
// RULE 3 — SPACERS ARE LOAD-BEARING:
//   The Spacer() in the header HStack and the Spacer(minLength: 8) at VStack bottom
//   must NOT be removed. They maintain correct layout under the fixed-height frame.
//
// ❌ NEVER: add .frame(height:) or .frame(idealHeight:) to this view
// ❌ NEVER: add popover.contentSize changes in navigate()
// ✅ SAFE: hc.rootView swap in navigate() — no size change
struct JobDetailView: View {
    let job: ActiveJob
    let onBack: () -> Void
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Back button + elapsed
            // ⚠️ The Spacer() here is load-bearing — do NOT remove (Rule 3)
            HStack(spacing: 6) {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                        Text("Jobs")
                            .font(.caption)
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

            // ── Steps list
            if job.steps.isEmpty {
                Text("No step data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(job.steps) { step in
                    Button(action: { openLog(step: step) }) {
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
                            Spacer()  // ⚠️ load-bearing — do NOT remove
                            Text(step.elapsed)
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                            Image(systemName: "arrow.up.right.square")
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

            Spacer(minLength: 8)  // ⚠️ load-bearing — absorbs remaining height (Rule 3)
        }
        // ⚠️ RULE 1: fill the fixed contentSize frame AppDelegate provides.
        // maxWidth: .infinity + maxHeight: .infinity + alignment: .top
        // pins all content to top-left within the popover frame.
        // ❌ NEVER use idealWidth, fixedSize, or fixed width/height here.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick += 1 }
        }
    }

    private func openLog(step: JobStep) {
        // Open GitHub Actions log URL anchored to the step number
        let base = job.htmlUrl ?? "https://github.com"
        let urlString = "\(base)#step:\(step.id)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
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
