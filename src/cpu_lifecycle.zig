//! Explicit CPU operations. Ordinary SYSINFO remains passive.
const std = @import("std");
const r4os = @import("r4os");
const a = r4os.abi;
pub fn run(sys: r4os.r4sys.Context, dev: r4os.r4dev.Context, args: []const u8) ?i32 {
    var tokens = std.mem.tokenizeAny(u8, args, " \t\r\n");
    var operation: ?u32 = null;
    var cpu: u32 = 0;
    while (tokens.next()) |token| {
        const prefixes = [_][]const u8{ "/CPU:", "/CPUOFFLINE:", "/CPUONLINE:" };
        var matched = false;
        for (prefixes, 0..) |prefix, i| {
            if (token.len >= prefix.len and std.ascii.eqlIgnoreCase(token[0..prefix.len], prefix)) {
                if (operation != null) {
                    sys.println("SYSINFO: specify one /CPU:n, /CPUOFFLINE:n or /CPUONLINE:n");
                    return 2;
                }
                cpu = std.fmt.parseInt(u32, token[prefix.len..], 10) catch {
                    sys.println("SYSINFO: invalid CPU index");
                    return 2;
                };
                operation = @intCast(i);
                matched = true;
                break;
            }
        }
        if (!matched) {
            if (operation != null or std.ascii.startsWithIgnoreCase(token, "/CPU")) {
                sys.println("SYSINFO: use exactly one /CPU:n, /CPUOFFLINE:n or /CPUONLINE:n");
                return 2;
            }
            // A CPU command must own the complete argument line, never run
            // incidentally alongside a registry/storage diagnostic switch.
            if (std.ascii.indexOfIgnoreCase(args, "/CPU") != null) {
                sys.println("SYSINFO: CPU command cannot be combined with other switches");
                return 2;
            }
        }
    }
    const op = operation orelse return null;
    if (!dev.hasFn("cpu_lifecycle")) {
        sys.println("SYSINFO: CPU lifecycle provider unavailable");
        return 2;
    }
    var info: a.CpuLifecycleInfo = .{};
    var rc = dev.cpuLifecycle(a.cpu_lifecycle_op_query, cpu, 0, &info);
    if (rc == a.cpu_lifecycle_ok and op != a.cpu_lifecycle_op_query) {
        var power: ?r4os.power_profiles.Client = null;
        switch (@import("power_profiles.zig").quiesceForCpuChange(sys)) {
            .absent => {},
            .ready => |client| power = client,
            .failure => {
                sys.println("SYSINFO: CPU change refused; POWERSVC return is unconfirmed");
                return 1;
            },
        }
        const epoch = info.epoch;
        rc = dev.cpuLifecycle(op, cpu, epoch, &info);
        if (rc != a.cpu_lifecycle_ok) {
            info = .{};
            _ = dev.cpuLifecycle(a.cpu_lifecycle_op_query, cpu, 0, &info);
        }
        if (power) |*client| if (!@import("power_profiles.zig").resumeAfterCpuChange(sys, client) and rc == a.cpu_lifecycle_ok) {
            rc = a.cpu_capabilities_error_busy;
        };
    }
    var buffer: [320]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "SYSINFO CPU {d}: result={d} state={s} epoch={d} available={d}/{d} reason={d} flags=0x{x} capacity-generation={d}", .{ cpu, rc, state(info.state), info.epoch, info.available_cpus, info.configured_cpus, info.reason, info.flags, info.capacity_generation }) catch "SYSINFO: CPU result unavailable";
    sys.println(text);
    return if (rc == a.cpu_lifecycle_ok) 0 else 1;
}
fn state(value: u32) []const u8 {
    return switch (value) {
        a.cpu_lifecycle_state_online => "online",
        a.cpu_lifecycle_state_offline => "offline",
        a.cpu_lifecycle_state_draining => "draining",
        a.cpu_lifecycle_state_parked => "parked",
        a.cpu_lifecycle_state_stop_pending => "stop-pending",
        a.cpu_lifecycle_state_failed => "failed",
        a.cpu_lifecycle_state_qualified => "qualified",
        else => "unavailable",
    };
}
