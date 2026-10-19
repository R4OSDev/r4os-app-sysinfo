//! Passive CPU catalogue presentation; never executes register probes or policy.
const std = @import("std");
const r4os = @import("r4os");
const a = r4os.abi;
fn text(bytes: []const u8) []const u8 {
    return std.mem.sliceTo(bytes, 0);
}
fn hardware(value: u32) []const u8 {
    return switch (value) {
        a.cpu_feature_hardware_absent => "absent",
        a.cpu_feature_hardware_present => "present",
        else => "unknown",
    };
}
fn enabled(value: u32) []const u8 {
    return switch (value) {
        a.cpu_feature_os_disabled => "disabled",
        a.cpu_feature_os_enabled => "enabled",
        a.cpu_feature_os_not_applicable => "no OS control",
        else => "unknown",
    };
}
fn header(sys: r4os.r4sys.Context, cap: a.CpuCapabilitiesInfo) void {
    var buffer: [384]u8 = undefined;
    sys.println(std.fmt.bufPrint(&buffer, "  CPU {d} capabilities: {s} family={d} model={d} stepping={d} epoch={d} capture={d} {s}", .{ cap.cpu_index, text(&cap.vendor_name), cap.family, cap.model, cap.stepping, cap.epoch, cap.capture_sequence, if (cap.flags & a.cpu_capabilities_flag_schedulable != 0) @as([]const u8, "available") else "offline" }) catch "  CPU capabilities unavailable");
    if (cap.flags & a.cpu_capabilities_flag_hypervisor_present != 0) {
        sys.println(std.fmt.bufPrint(&buffer, "    Hypervisor: {s} bounds={s} maximum=0x{x} raw-maximum=0x{x}", .{ if (text(&cap.hypervisor_name).len != 0) text(&cap.hypervisor_name) else @as([]const u8, "unknown"), if (cap.flags & a.cpu_capabilities_flag_hypervisor_valid != 0) @as([]const u8, "valid") else "unknown/invalid", cap.max_hypervisor_leaf, cap.raw_hypervisor_maximum }) catch "    Hypervisor identity unknown");
    }
    if (cap.flags & a.cpu_capabilities_flag_nominal_frequency != 0) {
        sys.println(std.fmt.bufPrint(&buffer, "    Nominal MHz: base={d} maximum={d} bus={d}; active frequency unknown", .{ cap.base_mhz, cap.maximum_mhz, cap.bus_mhz }) catch "    Nominal frequency unknown");
    } else sys.println("    Nominal and active frequency: unknown");
}
pub fn print(sys: r4os.r4sys.Context, dev: r4os.r4dev.Context) void {
    if (!dev.hasFn("cpu_capabilities")) {
        sys.println("  CPU capabilities: provider unavailable");
        return;
    }
    var first: a.CpuCapabilitiesInfo = .{};
    if (dev.cpuCapabilities(0, &first) != a.cpu_capabilities_ok) {
        sys.println("  CPU capabilities: capture unavailable");
        return;
    }
    for (0..first.configured_cpus) |cpu| {
        var cap: a.CpuCapabilitiesInfo = .{};
        if (dev.cpuCapabilities(@intCast(cpu), &cap) != a.cpu_capabilities_ok) {
            sys.println("  CPU capabilities: capture changing/unavailable");
            return;
        }
        header(sys, cap);
    }
    sys.println("  Feature details: SYSINFO /CPUFEATURES:n (passive; hardware, OS state and use are separate)");
}
pub fn run(sys: r4os.r4sys.Context, dev: r4os.r4dev.Context, args: []const u8) ?i32 {
    var tokens = std.mem.tokenizeAny(u8, args, " \t\r\n");
    const token = tokens.next() orelse return null;
    const prefix = "/CPUFEATURES:";
    if (!std.ascii.startsWithIgnoreCase(token, "/CPUFEATURES")) return null;
    if (!std.ascii.startsWithIgnoreCase(token, prefix) or tokens.next() != null) {
        sys.println("SYSINFO: use exactly one /CPUFEATURES:n");
        return 2;
    }
    const cpu = std.fmt.parseInt(u32, token[prefix.len..], 10) catch {
        sys.println("SYSINFO: invalid CPU index");
        return 2;
    };
    if (!dev.hasFn("cpu_capabilities") or !dev.hasFn("cpu_feature")) {
        sys.println("SYSINFO: CPU capability provider unavailable");
        return 2;
    }
    var cap: a.CpuCapabilitiesInfo = .{};
    const rc = dev.cpuCapabilities(cpu, &cap);
    if (rc != a.cpu_capabilities_ok) {
        sys.println("SYSINFO: CPU capture unavailable or index invalid");
        return 1;
    }
    header(sys, cap);
    var buffer: [320]u8 = undefined;
    sys.println(std.fmt.bufPrint(&buffer, "    Controls: valid=0x{x} CR0=0x{x} CR4=0x{x} XCR0=0x{x}; advertised XCR0=0x{x}", .{ cap.os_read_flags, cap.cr0, cap.cr4, cap.xcr0, cap.supported_xcr0 }) catch "    Controls unavailable");
    if (cap.feature_count > 256) {
        sys.println("SYSINFO: feature count exceeds presentation capacity");
        return 1;
    }
    for (0..cap.feature_count) |index| {
        var feature: a.CpuFeatureInfo = .{};
        if (dev.cpuFeature(cpu, cap.epoch, @intCast(index), &feature) != a.cpu_capabilities_ok) {
            sys.println("SYSINFO: CPU epoch/capture changed; query again explicitly");
            return 1;
        }
        sys.println(std.fmt.bufPrint(&buffer, "    {s}: hardware={s} OS={s} use=unknown{s} reason={d}", .{ text(&feature.name), hardware(feature.hardware_state), enabled(feature.os_state), if (feature.flags & a.cpu_feature_flag_module_required != 0) @as([]const u8, " module-required") else "", feature.reason }) catch "    Feature unavailable");
    }
    return 0;
}
