import SwiftUI

struct JobDetailView: View {
    let job: ActiveJob
    let onBack: () -> Void
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header
            HStack(spacing: 6) {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Jobs")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(job.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            // ── Steps
            if job.steps.isEmpty {
                Text(job.status == "queued" ? "Job is queued — no steps yet" : "No step data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                ForEach(job.steps) { step in
                    HStack(spacing: 8) {
                        stepIcon(for: step)
                            .frame(width: 14)
                        Text(step.name)
                            .font(.system(size: 12))
                            .foregroundColor(step.conclusion == "skipped" ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text(stepElapsed(step))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .opacity(step.conclusion == "skipped" ? 0.5 : 1.0)
                }
                .padding(.bottom, 6)
            }
        }
        .frame(minWidth: 320)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick += 1 }
        }
    }

    // MARK: - Step icon

    @ViewBuilder
    private func stepIcon(for step: JobStep) -> some View {
        switch step.conclusion {
        case "success":
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 11))
        case "failure":
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 11))
        case "skipped":
            Image(systemName: "minus.circle")
                .foregroundColor(.secondary)
                .font(.system(size: 11))
        case "cancelled":
            Image(systemName: "slash.circle")
                .foregroundColor(.secondary)
                .font(.system(size: 11))
        default:
            // in_progress or queued
            if step.status == "in_progress" {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 8, height: 8)
                    .padding(.leading, 2)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .padding(.leading, 2)
            }
        }
    }

    // MARK: - Elapsed

    private func stepElapsed(_ step: JobStep) -> String {
        // Force live recalc via tick for in_progress steps
        _ = tick
        return step.elapsed
    }
}
