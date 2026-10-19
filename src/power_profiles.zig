//! External profile intent and confirmed return; ordinary SYSINFO is passive.
const std = @import("std");
const r4os = @import("r4os");
const a = r4os.abi;
const timeout: r4os.app_services.Timeout = .{ .kind = a.timeout_kind_finite, .nanoseconds = 4_000_000_000 };
pub fn profileName(value: u32) []const u8 {
    return switch (value) {
        0 => "firmware",
        1 => "balanced",
        2 => "performance",
        3 => "saving",
        else => "unknown",
    };
}
fn stateName(value: u32) []const u8 {
    return switch (value) {
        a.power_profile_state_firmware => "firmware",
        a.power_profile_state_unsupported => "unsupported",
        a.power_profile_state_disabled => "hardware-disabled",
        a.power_profile_state_applied => "parameters-confirmed",
        a.power_profile_state_retained => "retained",
        a.power_profile_state_partial => "partial",
        a.power_profile_state_quiesced => "quiesced",
        else => "in-progress",
    };
}
fn line(sys: r4os.r4sys.Context, comptime format: []const u8, values: anytype) void {
    var buffer: [512]u8 = undefined;
    sys.println(std.fmt.bufPrint(&buffer, format, values) catch "POWERSVC: output unavailable");
}
pub fn show(sys: r4os.r4sys.Context, value: a.PowerProfileInfo) void {
    line(sys, "POWERSVC: selected={s} actual={s} generation={d} revision={d} applied={d}", .{ profileName(value.selected_profile), stateName(value.state), value.service_generation, value.revision, value.applied_revision });
    line(sys, "  CPUs={d}/{d} backend={d} workers={d} owned=0x{x} confirmed=0x{x} pending=0x{x}", .{ value.online_cpus, value.configured_cpus, value.backend_cpus, value.worker_count, value.owned_mask, value.applied_mask, value.pending_mask });
    line(sys, "  provider={d} config-error={d} last-error={d} CPU={d} reset-only-enabled={d}", .{ value.provider_generation, value.config_error, value.last_error, value.last_cpu, value.sticky_count });
    sys.println("  Abstract parameter receipts; delivered clock, boost, energy and thermal response are not measured here.");
}
fn openReady(sys: r4os.r4sys.Context) r4os.power_profiles.Open {
    const start = sys.ticks();
    const budget = @max(@as(u64, 1), sys.ticksFromMilliseconds(4000));
    while (true) {
        const elapsed = sys.ticks() -| start;
        if (elapsed >= budget) return .{ .failure = a.service_api_result_timeout };
        const remaining = r4os.time_contract.durationFromTicks(budget - elapsed, sys.monotonicHz()) catch
            return .{ .failure = a.service_api_result_timeout };
        const opened = r4os.power_profiles.Client.open(sys, r4os.time_contract.timeoutFinite(remaining));
        switch (opened) {
            .client => return opened,
            .failure => |rc| {
                if (rc != a.service_api_result_no_endpoint and rc != a.service_api_result_not_running) return opened;
                var service: a.ServiceInfo = .{};
                if (sys.serviceStatus("POWERSVC", &service) != 0 or
                    (service.state != a.service_state_starting and service.state != a.service_state_running) or
                    sys.programShouldClose()) return opened;
                if (sys.ticks() -| start >= budget) return .{ .failure = a.service_api_result_timeout };
                // START acknowledges a process before its endpoint is ready.
                // Only this initial passive open waits; the eventual profile
                // mutation is submitted once with the observed generation.
                sys.sleepTicks(1);
            },
        }
    }
}
pub fn run(sys: r4os.r4sys.Context, args: []const u8) ?i32 {
    if (std.ascii.indexOfIgnoreCase(args, "/POWER") == null) return null;
    var tokens = std.mem.tokenizeAny(u8, args, " \t\r\n");
    const token = tokens.next() orelse return null;
    if (!std.ascii.startsWithIgnoreCase(token, "/POWER")) return usage(sys);
    var command: []const u8 = "status";
    var cpu: ?u32 = null;
    if (std.ascii.startsWithIgnoreCase(token, "/POWERCPU:")) {
        cpu = std.fmt.parseInt(u32, token[10..], 10) catch return usage(sys);
    } else if (std.ascii.eqlIgnoreCase(token, "/POWER")) {} else if (std.ascii.startsWithIgnoreCase(token, "/POWER:")) {
        command = token[7..];
    } else return usage(sys);
    var sticky = false;
    if (tokens.next()) |extra| {
        if (!std.ascii.eqlIgnoreCase(extra, "/ENABLE")) return usage(sys);
        sticky = true;
    }
    if (tokens.next() != null) return usage(sys);
    var profile: ?u32 = null;
    for (0..4) |candidate| if (std.ascii.eqlIgnoreCase(command, profileName(@intCast(candidate)))) {
        profile = @intCast(candidate);
        break;
    };
    if (sticky and (cpu != null or profile == null or profile.? == a.power_profile_firmware)) return usage(sys);
    if (profile == null and !std.ascii.eqlIgnoreCase(command, "status") and !std.ascii.eqlIgnoreCase(command, "quiesce") and !std.ascii.eqlIgnoreCase(command, "resume") and !std.ascii.eqlIgnoreCase(command, "reload")) return usage(sys);
    var client = switch (openReady(sys)) {
        .client => |value| value,
        .failure => |rc| {
            line(sys, "POWERSVC unavailable: {d}", .{rc});
            return 1;
        },
    };
    if (cpu) |index| {
        switch (client.cpu(index, timeout)) {
            .value => |value| {
                line(sys, "POWERSVC CPU {d}: backend={d} state={s} epoch={d} provider={d} lease={d} revision={d} applied={d} flags=0x{x}", .{ index, value.backend, stateName(value.state), value.cpu_epoch, value.provider_generation, value.lease, value.revision, value.applied_revision, value.flags });
                line(sys, "  abstract min={d} max={d} desired={d} EPP={d} baseline=0x{x} written=0x{x} observed=0x{x} valid=0x{x} error={d}", .{ value.minimum, value.maximum, value.desired, value.epp, value.baseline_request, value.last_written, value.observed_request, value.valid_mask, value.last_error });
                return 0;
            },
            .failure, .remote_failure => |rc| {
                line(sys, "POWERSVC CPU query failed: {d}", .{rc});
                return 1;
            },
            .timed_out => {
                sys.println("POWERSVC query timed out");
                return 1;
            },
        }
    }
    const result = if (profile) |selected| client.select(selected, sticky, timeout) else if (std.ascii.eqlIgnoreCase(command, "quiesce")) client.quiesce(timeout) else if (std.ascii.eqlIgnoreCase(command, "resume")) client.resumeProfile(timeout) else if (std.ascii.eqlIgnoreCase(command, "reload")) client.reload(timeout) else client.status(timeout);
    return switch (result) {
        .value => |value| blk: {
            show(sys, value);
            break :blk if (value.config_error == 0 and value.pending_mask == 0) @as(i32, 0) else 1;
        },
        .failure, .remote_failure => |rc| blk: {
            line(sys, "POWERSVC request refused: {d}", .{rc});
            break :blk 1;
        },
        .timed_out => blk: {
            sys.println("POWERSVC request timed out; outcome unknown. Query status before retrying.");
            break :blk 1;
        },
    };
}
fn usage(sys: r4os.r4sys.Context) i32 {
    sys.println("SYSINFO /POWER[:status|firmware|balanced|performance|saving|quiesce|resume|reload] or /POWERCPU:n");
    sys.println("Only profile selection accepts /ENABLE, explicit reset-only hardware activation consent.");
    return 2;
}
pub fn quiesceForCpuChange(sys: r4os.r4sys.Context) union(enum) { absent, ready: r4os.power_profiles.Client, failure: i32 } {
    var service: a.ServiceInfo = .{};
    const rc = sys.serviceStatus("POWERSVC", &service);
    if (rc == a.service_api_result_not_found or (rc == 0 and (service.state == a.service_state_stopped or service.state == a.service_state_disabled))) return .absent;
    if (rc != 0) return .{ .failure = rc };
    var client = switch (openReady(sys)) {
        .client => |value| value,
        .failure => |reason| return .{ .failure = reason },
    };
    return switch (client.quiesce(timeout)) {
        .value => |value| if (value.owned_mask == 0 and value.pending_mask == 0 and value.worker_count == 0 and value.flags & a.power_profile_flag_quiesced != 0) .{ .ready = client } else .{ .failure = a.cpu_capabilities_error_busy },
        .failure, .remote_failure => |reason| .{ .failure = reason },
        .timed_out => .{ .failure = a.service_api_result_timeout },
    };
}
pub fn resumeAfterCpuChange(sys: r4os.r4sys.Context, client: *r4os.power_profiles.Client) bool {
    return switch (client.resumeProfile(timeout)) {
        .value => |value| blk: {
            show(sys, value);
            break :blk value.pending_mask == 0;
        },
        else => blk: {
            sys.println("POWERSVC resume unconfirmed; profile remains quiesced. Query /POWER.");
            break :blk false;
        },
    };
}
