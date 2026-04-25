import SwiftUI

// MARK: - Step Log View (Phase 2)

struct StepLogView: View {
    let job: ActiveJob
    let step: JobStep
    let scope: String
    let onBack: () -> Void

    @State private var lines: [String] = []
    @State private var isLoading = true
    @State private var truncated = false

    private let maxLines = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header
            HStack(spacing: 6) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(step.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(job.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // ── Log content
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView().padding(.vertical, 16)
                    Spacer()
                }
            } else if lines.isEmpty {
                Text("No log output available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                if truncated {
                    Text("(showing last \(maxLines) lines)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .padding(.bottom, 2)
                }
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.85))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(minWidth: 320)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loadLog() }
    }

    // MARK: - Data

    private func loadLog() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let (logLines, wasTruncated) = fetchStepLog(
                jobID: job.id,
                stepNumber: step.id,
                scope: scope,
                maxLines: maxLines
            )
            DispatchQueue.main.async {
                lines = logLines
                truncated = wasTruncated
                isLoading = false
            }
        }
    }
}
