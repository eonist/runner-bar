import Foundation
import Darwin

// ── Model ────────────────────────────────────────────────────────────────────

struct SystemStats {
    var cpuPct: Double       // 0–100
    var memUsedGB: Double    // active + wired pages only
    var memTotalGB: Double   // hw.memsize
    var diskUsedGB: Double   // total - free
    var diskTotalGB: Double  // volumeTotalCapacity
    var diskFreeGB: Double   // volumeAvailableCapacityForImportantUsage (APFS-correct)
    var diskFreePct: Double  // (freeGB / totalGB) * 100

    static let zero = SystemStats(
        cpuPct: 0, memUsedGB: 0, memTotalGB: 16,
        diskUsedGB: 0, diskTotalGB: 460, diskFreeGB: 460, diskFreePct: 100
    )
}

// ── ViewModel ────────────────────────────────────────────────────────────────

import Combine

final class SystemStatsViewModel: ObservableObject {
    @Published var stats: SystemStats = .zero

    private var timer: Timer?
    private var prevTicks: (user: Double, sys: Double, total: Double) = (0, 0, 0)

    init() {
        sample()   // immediate first read
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async { self?.sample() }
        }
    }

    deinit { timer?.invalidate() }

    // ── CPU ──────────────────────────────────────────────────────────────────
    // host_processor_info() mach ticks — no shell, no top, no ps

    private func cpuPercent() -> Double {
        var cpuInfo: processor_info_array_t?
        var msgType = natural_t(0)
        var numCPUInfo = mach_msg_type_number_t(0)

        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &msgType, &cpuInfo, &numCPUInfo) == KERN_SUCCESS,
              let info = cpuInfo else { return 0 }

        let numCPUs = Int(msgType)
        var userTicks = 0.0
        var sysTicks  = 0.0
        var totalTicks = 0.0

        for i in 0 ..< numCPUs {
            let base = Int32(CPU_STATE_MAX) * Int32(i)
            let u = Double(info[Int(base) + Int(CPU_STATE_USER)])
            let s = Double(info[Int(base) + Int(CPU_STATE_SYSTEM)])
            let id = Double(info[Int(base) + Int(CPU_STATE_IDLE)])
            let n = Double(info[Int(base) + Int(CPU_STATE_NICE)])
            userTicks  += u + n
            sysTicks   += s
            totalTicks += u + s + id + n
        }

        vm_deallocate(mach_task_self_,
                      vm_address_t(bitPattern: cpuInfo),
                      vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride))

        let dUser  = userTicks - prevTicks.user
        let dSys   = sysTicks  - prevTicks.sys
        let dTotal = totalTicks - prevTicks.total

        prevTicks = (userTicks, sysTicks, totalTicks)

        guard dTotal > 0 else { return 0 }
        return min(100, ((dUser + dSys) / dTotal) * 100)
    }

    // ── MEM ──────────────────────────────────────────────────────────────────
    // active + wired only — excludes compressed, inactive, file-backed/cache

    private func memStats() -> (used: Double, total: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard kr == KERN_SUCCESS else { return (0, 16) }

        let pageSize = Double(vm_kernel_page_size)
        let gb = 1024.0 * 1024.0 * 1024.0
        let used = Double(stats.active_count + stats.wire_count) * pageSize / gb

        var memSize: UInt64 = 0
        var memSizeSize = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memSize, &memSizeSize, nil, 0)
        let total = Double(memSize) / gb

        return (used, total)
    }

    // ── DISK ─────────────────────────────────────────────────────────────────
    // volumeAvailableCapacityForImportantUsage — APFS-correct, not purgeable-inflated

    private func diskStats() -> (used: Double, total: Double, free: Double, freePct: Double) {
        let url = URL(fileURLWithPath: "/")
        let gb = 1024.0 * 1024.0 * 1024.0

        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]),
        let totalBytes = values.volumeTotalCapacity,
        let freeBytes  = values.volumeAvailableCapacityForImportantUsage else {
            return (0, 460, 460, 100)
        }

        let total   = Double(totalBytes) / gb
        let free    = Double(freeBytes)  / gb
        let used    = total - free
        let freePct = total > 0 ? (free / total) * 100 : 100

        return (used, total, free, freePct)
    }

    // ── Sample ───────────────────────────────────────────────────────────────

    private func sample() {
        let cpu  = cpuPercent()
        let mem  = memStats()
        let disk = diskStats()

        let s = SystemStats(
            cpuPct:      cpu,
            memUsedGB:   mem.used,
            memTotalGB:  mem.total,
            diskUsedGB:  disk.used,
            diskTotalGB: disk.total,
            diskFreeGB:  disk.free,
            diskFreePct: disk.freePct
        )

        DispatchQueue.main.async { self.stats = s }
    }
}
