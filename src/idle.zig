// Copyright 2026 R4. SPDX-License-Identifier: Apache-2.0
//! Passive idle declarations and software receipts; no forced CPU sleep.
const std = @import("std");
const r = @import("r4os");
const a = r.abi;
pub fn run(sys: r.r4sys.Context, dev: r.r4dev.Context, args: []const u8) ?i32 {
    const text = std.mem.trim(u8, args, " \t\r\n");
    if (!std.ascii.startsWithIgnoreCase(text, "/CPUIDLE")) return null;
    if (text.len < 10 or text[8] != ':') {
        sys.println("SYSINFO /CPUIDLE:<cpu>  passive idle receipt");
        return 1;
    }
    const cpu = std.fmt.parseInt(u32, text[9..], 10) catch return 1;
    var v: a.CpuIdleInfo = .{};
    const rc = dev.cpuIdleInfo(cpu, &v);
    var b: [512]u8 = undefined;
    sys.println(std.fmt.bufPrint(&b, "CPUIDLE CPU={d} result={d} state={d} reason={d} epoch={d} firmware={d} policy={d}", .{ cpu, rc, v.state, v.reason, v.epoch, v.firmware_generation, v.policy_generation }) catch "CPUIDLE output unavailable");
    if (rc == a.err_no_fn) {
        sys.println("CPUIDLE unavailable");
        return 0;
    }
    if (rc != 0 or v.cpu_index != cpu or v.version != 1 or v.size < @sizeOf(a.CpuIdleInfo)) return 1;
    if (v.source == 1 and v.state_count != 0 and v.reason != a.cpu_idle_reason_malformed) {
        sys.println(std.fmt.bufPrint(&b, "CPUIDLE declared CST states={d} index={d}", .{ v.state_count, v.selected_index }) catch "CPUIDLE output unavailable");
        if (v.entry_method == 1 and v.cstate_type == 2) {
            sys.println(std.fmt.bufPrint(&b, "CPUIDLE CST candidate C={d} hint=0x{x} latency_us={d} declared_power_mW={d}", .{ v.cstate_type, v.entry_hint, v.latency_us, v.declared_power_mw }) catch "CPUIDLE output unavailable");
        } else sys.println("CPUIDLE CST entry unavailable for the supported local method");
        sys.println("CPUIDLE CST minimum residency property: unavailable");
    } else if (v.source == 2 and v.state_count != 0 and v.reason != a.cpu_idle_reason_malformed) {
        sys.println(std.fmt.bufPrint(&b, "CPUIDLE declared LPI states={d} index={d} latency_us={d} min_residency_us={d} context_loss=0x{x}", .{ v.state_count, v.selected_index, v.latency_us, v.min_residency_us, v.context_loss }) catch "CPUIDLE output unavailable");
        sys.println("CPUIDLE LPI entry and declared power: unavailable");
    } else sys.println("CPUIDLE firmware entry data: unavailable or invalid");
    sys.println(std.fmt.bufPrint(&b, "CPUIDLE software attempts={d} HLT={d} cancelled={d} active={d} elapsed_ns={d} revision={d}", .{ v.entry_attempts, v.hlt_fallbacks, v.cancelled_entries, v.active_entries, v.elapsed_ns, v.descriptor_revision }) catch "CPUIDLE output unavailable");
    sys.println("CPUIDLE hardware residency, wake latency and energy: unavailable; declarations and attempts are not measurements");
    return if (v.residency_ns == 0 and v.wake_latency_ns == 0 and v.energy_uj == 0) 0 else 1;
}
