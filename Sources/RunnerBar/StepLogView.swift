import AppKit
import SwiftUI

// ⚠️ REGRESSION GUARD — frame rules (ref #52 #54 #57)
//
// ── ARCHITECTURE ──────────────────────────────────────────────────────────────
//   navigate() in AppDelegate does rootView swap ONLY — zero size changes.
//   This view fills whatever frame AppDelegate set at open time (mainView fittingSize).
//   ScrollView ensures log content never overflows that frame.
//
// ── RULES ─────────────────────────────────────────────────────────────────────
//   ✔ Root: .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.top)
//   ✔ Log text MUST be inside ScrollView
//   ✔ Header (back + step name) MUST be outside ScrollView — always visible
//   ❌ NEVER add idealWidth — only meaningful under preferredContentSize (FORBIDDEN)
//   ❌ NEVER add .frame(height:) — fights AppDelegate's fixed frame
//   ❌ NEVER add .fixedSize() — collapses view
//   ❌ NEVER call navigate() directly — use onBack callback
struct StepLogView: View {
    let job: ActiveJob
    let step: JobStep
    let onBack: () -> Void

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

            Text(step.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            Divider()

            // ── Log body: INSIDE ScrollView
            // ⚠️ ScrollView is REQUIRED — log may be many lines
            ScrollView(.vertical, showsIndicators: true) {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small).padding(.vertical, 20)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { loadLog() }
    }

    private func loadLog() {
        isLoading = true
        let jobID   = job.id
        let stepNum = step.id  // 1-based

        // Extract owner/repo from job.htmlUrl (ground truth).
        // Format: https://github.com/{owner}/{repo}/actions/runs/{run}/jobs/{id}
        // Split by "/": ["","","github.com",{owner},{repo},...]
        // indices:         0   1       2           3       4
        //
        // Fallback to first repo-scoped ScopeStore entry if htmlUrl is nil/malformed.
        let scope: String = {
            if let url = job.htmlUrl {
                let parts = url.components(separatedBy: "/")
                // parts[3] = owner, parts[4] = repo (URL has leading "https://github.com")
                if parts.count >= 5 {
                    let owner = parts[3]
                    let repo  = parts[4]
                    if !owner.isEmpty && !repo.isEmpty {
                        return "\(owner)/\(repo)"
                    }
                }
            }
            // Fallback: first repo-scoped scope
            return ScopeStore.shared.scopes.first(where: { $0.contains("/") }) ?? ""
        }()

        DispatchQueue.global(qos: .userInitiated).async {
            let text = fetchStepLog(jobID: jobID, stepNumber: stepNum, scope: scope)
            DispatchQueue.main.async {
                logText   = text ?? ""
                isLoading = false
            }
        }
    }
}
