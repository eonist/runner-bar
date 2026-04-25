import AppKit
import SwiftUI

// ⚠️ REGRESSION GUARD — frame rules (ref #52 #54 #57)
//
// ── ARCHITECTURE ──────────────────────────────────────────────────────────────
//   This view is displayed by navigate() in AppDelegate.
//   navigate() does a rootView swap only — ZERO size changes.
//   This view therefore receives whatever frame AppDelegate set at open time
//   (from mainView()'s fittingSize). It must always fit that frame.
//
// ── RULES ─────────────────────────────────────────────────────────────────────
//   ✔ Root: .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.top)
//       Fills the fixed frame. ScrollView ensures content never overflows.
//   ✔ Log text MUST be inside ScrollView — text may be taller than frame
//   ✔ Header (back + step name) MUST be outside ScrollView — always visible
//   ❌ NEVER add idealWidth — only meaningful under preferredContentSize (FORBIDDEN)
//   ❌ NEVER add .frame(height:) — fights AppDelegate's fixed frame
//   ❌ NEVER add .fixedSize() — collapses the view
//   ❌ NEVER call navigate() or any AppDelegate method from here directly
//        — always use the onBack callback provided at construction time
struct StepLogView: View {
    let job: ActiveJob
    let step: JobStep
    let onBack: () -> Void

    // nil  = still loading
    // ""   = fetch returned empty / unavailable
    // text = log content
    @State private var logText: String? = nil
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header: always visible, OUTSIDE ScrollView
            // ⚠️ Spacer() is load-bearing — do NOT remove
            HStack(spacing: 6) {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.caption)
                        Text("Steps").font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()  // ⚠️ load-bearing — do NOT remove
                Text(step.elapsed)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)

            // Step name
            Text(step.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            Divider()

            // ── Log body: INSIDE ScrollView
            // ⚠️ ScrollView is REQUIRED — log text may be many lines
            ScrollView(.vertical, showsIndicators: true) {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                            .padding(.vertical, 20)
                        Spacer()
                    }
                } else if let text = logText, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                } else {
                    Text("Log not available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
        }
        // ⚠️ Fill AppDelegate's fixed frame. Pin to top.
        // ScrollView above ensures log text never overflows.
        // ❌ NEVER add idealWidth — not meaningful in current fittingSize architecture
        // ❌ NEVER add .frame(height:) — fights AppDelegate's frame
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { loadLog() }
    }

    // Fetch log on a background thread so the UI stays responsive.
    // Sets isLoading=false when done regardless of result.
    private func loadLog() {
        isLoading = true
        let jobID    = job.id
        let stepNum  = step.id   // 1-based step number
        // Use the first repo-scoped scope that matches this job's htmlUrl.
        // fetchStepLog requires a repo scope ("owner/repo" form).
        let scope = ScopeStore.shared.scopes.first(where: { $0.contains("/") }) ?? ""
        DispatchQueue.global(qos: .userInitiated).async {
            let text = fetchStepLog(jobID: jobID, stepNumber: stepNum, scope: scope)
            DispatchQueue.main.async {
                logText   = text ?? ""
                isLoading = false
            }
        }
    }
}
