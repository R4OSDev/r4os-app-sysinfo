// Copyright 2026 R4. SPDX-License-Identifier: Apache-2.0
//! Explicit passive firmware transport query. Loading AML alone never proves
//! a usable CPU performance interface, physical clock change or energy saving.
const std = @import("std");
const r = @import("r4os");
const a = r.abi;
pub fn run(sys: r.r4sys.Context, dev: r.r4dev.Context, args: []const u8) ?i32 {
    const text = std.mem.trim(u8, args, " \t\r\n");
    if (!std.ascii.startsWithIgnoreCase(text, "/CPUFW")) return null;
    if (text.len < 8 or text[6] != ':') {
        sys.println("SYSINFO /CPUFW:<cpu>  passive ACPI performance receipt");
        return 1;
    }
    const cpu = std.fmt.parseInt(u32, text[7..], 10) catch return 1;
    var cap: a.CpuCapabilitiesInfo = .{};
    if (dev.cpuCapabilities(cpu, &cap) != 0) return 1;
    const request: a.CpuPerformanceRequest = .{ .cpu_index = cpu, .epoch = cap.epoch };
    var info: a.CpuFirmwareInfo = .{};
    const rc = dev.cpuFirmwarePerformance(&request, &info);
    var buffer: [512]u8 = undefined;
    sys.println(std.fmt.bufPrint(&buffer, "CPUFW CPU={d} result={d} backend={d} state={d} provider={d} firmware={d} epoch={d}", .{ cpu, rc, info.backend, info.state, info.provider_generation, info.firmware_generation, info.epoch }) catch "CPUFW output unavailable");
    if (rc == a.cpu_capabilities_error_unsupported or rc == a.err_no_fn) {
        sys.println("CPUFW transport unavailable; no hardware control attempted");
        return 0;
    }
    if (rc != 0) return 1;
    if (info.cpu_index != cpu or info.epoch != cap.epoch or info.provider_generation == 0 or info.firmware_generation == 0) return 1;
    sys.println(std.fmt.bufPrint(&buffer, "CPUFW domain=0x{x} coordination=0x{x} members={d} valid=0x{x} lease={d} revision={d} error={d}", .{ info.domain_mask, info.coordination, info.domain_cpus, info.valid_mask, info.lease, info.revision, info.last_error }) catch "CPUFW output unavailable");
    if (info.valid_mask & a.cpu_firmware_valid_range != 0) sys.println(std.fmt.bufPrint(&buffer, "CPUFW abstract lowest={d} highest={d} nominal={d} nonlinear={d} min={d} max={d} desired={d} EPP={d}", .{ info.lowest, info.highest, info.nominal, info.efficient, info.minimum, info.maximum, info.desired, info.epp }) catch "CPUFW output unavailable");
    sys.println("CPUFW query is passive; a missing or unsupported firmware contract grants no control");
    return 0;
}
