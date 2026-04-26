import SwiftUI

// ── System stats: ONE row, never bleeds to second row ────────────────────────
//
// CPU [▓░░] 29.7%  MEM [▓▓▓░] 1.6/16.0GB  DISK [▓▓▓▓▓░] 352/460GB (free: 108GB 24%)
//
// RULE: .lineLimit(1) is load-bearing. Do not remove.
// RULE: bar width 20pt, height 5pt. Do not grow bars — DISK label is long.
// RULE: segment spacing 6pt. Do not increase — 340pt popover width is tight.

struct SystemStatsView: View {
    let stats: SystemStats

    var body: some View {
        HStack(spacing: 6) {
            cpuSegment
            memSegment
            diskSegment
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // ── CPU ──────────────────────────────────────────────────────────────────

    private var cpuSegment: some View {
        HStack(spacing: 4) {
            Text("CPU").font(.caption2).foregroundColor(.secondary)
            bar(fraction: stats.cpuPct / 100, color: usageColor(pct: stats.cpuPct))
            Text(String(format: "%.1f%%", stats.cpuPct))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(usageColor(pct: stats.cpuPct))
        }
    }

    // ── MEM ──────────────────────────────────────────────────────────────────

    private var memSegment: some View {
        let usedPct = stats.memTotalGB > 0 ? (stats.memUsedGB / stats.memTotalGB) * 100 : 0
        return HStack(spacing: 4) {
            Text("MEM").font(.caption2).foregroundColor(.secondary)
            bar(fraction: usedPct / 100, color: usageColor(pct: usedPct))
            Text(String(format: "%.1f/%.1fGB", stats.memUsedGB, stats.memTotalGB))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(usageColor(pct: usedPct))
        }
    }

    // ── DISK ─────────────────────────────────────────────────────────────────
    // Bar fills on used%. Color on free% (SonarQube threshold).

    private var diskSegment: some View {
        let usedPct = stats.diskTotalGB > 0 ? (stats.diskUsedGB / stats.diskTotalGB) * 100 : 0
        let color   = diskColor(freePct: stats.diskFreePct)
        return HStack(spacing: 4) {
            Text("DISK").font(.caption2).foregroundColor(.secondary)
            bar(fraction: usedPct / 100, color: color)
            Text(String(format: "%d/%dGB (free: %dGB %d%%)",
                        Int(stats.diskUsedGB.rounded()),
                        Int(stats.diskTotalGB.rounded()),
                        Int(stats.diskFreeGB.rounded()),
                        Int(stats.diskFreePct.rounded())))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    // ── Bar ──────────────────────────────────────────────────────────────────

    private func bar(fraction: Double, color: Color) -> some View {
        GeometryReader { _ in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.1))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 20 * max(0, min(1, fraction)))
            }
        }
        .frame(width: 20, height: 5)
    }

    // ── Colors ───────────────────────────────────────────────────────────────

    /// CPU / MEM: color on used%
    private func usageColor(pct: Double) -> Color {
        if pct > 85 { return .red }
        if pct > 60 { return .yellow }
        return .green
    }

    /// DISK: color on free% — SonarQube needs ≥10% free to run
    private func diskColor(freePct: Double) -> Color {
        if freePct < 10 { return .red }
        if freePct < 20 { return .yellow }
        return .green
    }
}
