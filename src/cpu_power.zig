//! A cached view never starts sampling, workers or power management.
const std = @import("std");
const r4os = @import("r4os");
const a = r4os.abi;
fn state(value: u32) []const u8 {
    return switch (value) {
        a.cpu_power_state_no_provider => "provider unavailable",
        a.cpu_power_state_no_sample => "no sample",
        a.cpu_power_state_observed => "observed",
        a.cpu_power_state_stale => "stale",
        a.cpu_power_state_unsupported => "unsupported CPU model",
        a.cpu_power_state_virtual => "virtual; physical sensors unavailable",
        else => "unknown",
    };
}
fn line(sys: r4os.r4sys.Context, comptime fmt: []const u8, args: anytype) void {
    var buffer: [384]u8 = undefined;
    sys.println(std.fmt.bufPrint(&buffer, fmt, args) catch "  CPU observation unavailable");
}
fn get(dev: r4os.r4dev.Context, cpu: u32, value: *a.CpuPowerInfo) bool {
    var cap: a.CpuCapabilitiesInfo = .{};
    return dev.cpuCapabilities(cpu, &cap) == 0 and dev.cpuPowerInfo(cpu, cap.epoch, value) == 0;
}
fn show(sys: r4os.r4sys.Context, value: a.CpuPowerInfo) void {
    line(sys, "  CPU {d}: {s}; profile={s}; epoch={d} provider={d} sequence={d}", .{ value.cpu_index, state(value.state), std.mem.sliceTo(&value.profile_name, 0), value.epoch, value.provider_generation, value.sequence });
    if (value.flags & a.cpu_power_flag_sampled != 0) {
        const now = sys.monotonicNanoseconds();
        line(sys, "    Captured={d} ns, clock={d}/{d}, interval={d} ns", .{ value.captured_ns, value.clock_source, value.clock_generation, value.interval_ns });
        if (now != null and now.? >= value.captured_ns) line(sys, "    Age={d} ns (cached observation)", .{now.? - value.captured_ns});
    }
    if (value.valid_mask & a.cpu_power_valid_active_hz != 0) line(sys, "    Active C0 average={d} Hz; reference={d} Hz", .{ value.active_hz, value.reference_hz }) else sys.println("    Active C0 average: unknown");
    if (value.valid_mask & a.cpu_power_valid_temperature != 0) line(sys, "    Temperature={d} mdegC (1000 mdegC = 1 C)", .{value.temperature_millic}) else sys.println("    Temperature: unknown");
    if (value.valid_mask & a.cpu_power_valid_microcode != 0) line(sys, "    Microcode revision=0x{x}", .{value.microcode_revision}) else sys.println("    Microcode revision: unknown");
    if (value.valid_mask & a.cpu_power_valid_thermal_status != 0) line(sys, "    Thermal current=0x{x}, sticky history=0x{x}", .{ value.thermal_current, value.thermal_history }) else sys.println("    Thermal current/history: unknown");
    if (value.valid_mask & (a.cpu_power_valid_package_energy | a.cpu_power_valid_package_scope) == a.cpu_power_valid_package_energy | a.cpu_power_valid_package_scope) {
        if (value.cpu_index == value.package_leader) line(sys, "    Package finite energy counter={d} uJ ({d} bits, ESU={d}, mask=0x{x})", .{ value.package_energy_uj, value.package_energy_bits, value.energy_exponent, value.package_mask }) else line(sys, "    Package energy: shared domain, see CPU {d}", .{value.package_leader});
    } else sys.println("    Package energy/scope: unknown");
    if (value.valid_mask & (a.cpu_power_valid_core_energy | a.cpu_power_valid_core_scope) == a.cpu_power_valid_core_energy | a.cpu_power_valid_core_scope) {
        if (value.cpu_index == value.core_leader) line(sys, "    {s} finite energy counter={d} uJ ({d} bits, ESU={d}, mask=0x{x})", .{ if (value.profile == a.cpu_power_profile_intel_haswell) @as([]const u8, "PP0/package-cores") else "Core", value.core_energy_uj, value.core_energy_bits, value.energy_exponent, value.core_mask }) else line(sys, "    Core/domain energy: shared domain, see CPU {d}", .{value.core_leader});
    } else sys.println("    Core/domain energy/scope: unknown");
    if (value.flags & a.cpu_power_flag_energy_discontinuity != 0) sys.println("    Energy counter descended: wrap or reset; no accumulated total or watts");
    line(sys, "    Valid=0x{x}, faults=0x{x}, unsupported=0x{x}", .{ value.valid_mask, value.fault_mask, value.unsupported_mask });
}
pub fn print(sys: r4os.r4sys.Context, dev: r4os.r4dev.Context) void {
    if (!dev.hasFn("cpu_power_info")) {
        sys.println("  CPUPOWER: provider unavailable");
        return;
    }
    var first: a.CpuCapabilitiesInfo = .{};
    if (dev.cpuCapabilities(0, &first) != 0) return;
    var sampled: u32 = 0;
    var installed: u32 = 0;
    for (0..first.configured_cpus) |index| {
        var value: a.CpuPowerInfo = .{};
        if (!get(dev, @intCast(index), &value)) {
            sys.println("  CPUPOWER: observation changing");
            return;
        }
        if (value.flags & a.cpu_power_flag_installed != 0) installed += 1;
        if (value.flags & a.cpu_power_flag_sampled != 0) sampled += 1;
    }
    line(sys, "  CPUPOWER: cached observations {d}/{d}, provider on {d}; details: SYSINFO /CPUPOWER", .{ sampled, first.configured_cpus, installed });
}
pub fn run(sys: r4os.r4sys.Context, dev: r4os.r4dev.Context, args: []const u8) ?i32 {
    var tokens = std.mem.tokenizeAny(u8, args, " \t\r\n");
    const token = tokens.next() orelse return null;
    if (!std.ascii.startsWithIgnoreCase(token, "/CPUPOWER")) return null;
    if (tokens.next() != null) return 2;
    var cpu: ?u32 = null;
    if (!std.ascii.eqlIgnoreCase(token, "/CPUPOWER")) {
        if (!std.ascii.startsWithIgnoreCase(token, "/CPUPOWER:")) return 2;
        cpu = std.fmt.parseInt(u32, token[10..], 10) catch return 2;
    }
    if (!dev.hasFn("cpu_power_info")) {
        sys.println("SYSINFO: CPUPOWER unavailable");
        return 2;
    }
    var first: a.CpuCapabilitiesInfo = .{};
    if (dev.cpuCapabilities(0, &first) != 0 or (cpu != null and cpu.? >= first.configured_cpus)) return 2;
    sys.println("CPUPOWER: passive cached view; explicit refresh: SPECTRA CHECK SMP /POWER");
    for (0..first.configured_cpus) |index| {
        if (cpu != null and cpu.? != index) continue;
        var value: a.CpuPowerInfo = .{};
        if (!get(dev, @intCast(index), &value)) return 1;
        show(sys, value);
    }
    return 0;
}
