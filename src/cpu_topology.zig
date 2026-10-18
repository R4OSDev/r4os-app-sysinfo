const r4os = @import("r4os");
const abi = r4os.abi;
fn number(sys: *const r4os.r4sys.Context, value: u64) void {
    sys.printU64(value);
}
fn bytes(sys: *const r4os.r4sys.Context, value: u64) void {
    if (value % (1024 * 1024) == 0) {
        number(sys, value / (1024 * 1024));
        sys.write("MB");
    } else if (value % 1024 == 0) {
        number(sys, value / 1024);
        sys.write("KB");
    } else {
        number(sys, value);
        sys.write("B");
    }
}
pub fn print(sys: *const r4os.r4sys.Context, dev: *const r4os.r4dev.Context, ok: *bool) void {
    sys.write("  CPU topology: ");
    if (!dev.hasFn("cpu_topology")) {
        sys.write("not available\r\n");
        return;
    }
    var first: abi.CpuTopologyInfo = .{};
    const initial = dev.cpuTopology(0, &first);
    if (initial != abi.cpu_topology_result_ok) {
        sys.write("not ready\r\n");
        if (initial != abi.cpu_topology_result_busy and initial != abi.cpu_topology_result_end) ok.* = false;
        return;
    }
    if (first.configured_cpus == 0) {
        sys.write("invalid catalog\r\n");
        ok.* = false;
        return;
    }
    number(sys, first.configured_cpus);
    sys.write(" configured");
    var capacity: abi.CpuCapacity = .{};
    if (sys.cpuCapacity(&capacity) == abi.thread_ok) {
        sys.write(", ");
        number(sys, capacity.available_cpus);
        sys.write(" schedulable");
    }
    sys.write("\r\n");
    for (0..first.configured_cpus) |index| {
        var info: abi.CpuTopologyInfo = .{};
        if (dev.cpuTopology(@intCast(index), &info) != abi.cpu_topology_result_ok or info.version != 1 or
            info.size != @sizeOf(abi.CpuTopologyInfo) or info.cpu_index != index or info.configured_cpus != first.configured_cpus)
        {
            sys.write("    CPU record unavailable\r\n");
            ok.* = false;
            return;
        }
        sys.write("    CPU ");
        number(sys, info.cpu_index);
        sys.write(" APIC ");
        number(sys, info.apic_id);
        if ((info.flags & abi.cpu_topology_flag_acpi_uid) != 0) {
            sys.write(" ACPI ");
            number(sys, info.acpi_uid);
        } else sys.write(" ACPI unknown");
        sys.write(if ((info.flags & abi.cpu_topology_flag_schedulable) != 0) " available" else " offline");
        if ((info.flags & abi.cpu_topology_flag_geometry) != 0) {
            sys.write(" package ");
            number(sys, info.package_id);
            sys.write(" core ");
            number(sys, info.core_id);
            sys.write(" SMT ");
            number(sys, info.thread_id);
        } else {
            sys.write(" core/package unknown");
        }
        if ((info.flags & abi.cpu_topology_flag_captured) != 0) {
            sys.write(" ");
            sys.write(&info.vendor_name);
        }
        if ((info.flags & abi.cpu_topology_flag_core_type) != 0) {
            sys.write(" type ");
            number(sys, info.core_type);
        }
        if (dev.hasFn("cpu_cache_topology")) for (0..info.cache_count) |ordinal| {
            var cache: abi.CpuCacheTopologyInfo = .{};
            if (dev.cpuCacheTopology(info.cpu_index, @intCast(ordinal), &cache) != abi.cpu_topology_result_ok or
                cache.version != 1 or cache.size != @sizeOf(abi.CpuCacheTopologyInfo) or cache.cpu_index != info.cpu_index or
                cache.cache_index != ordinal or cache.start_epoch != info.start_epoch)
            {
                ok.* = false;
                break;
            }
            sys.write(" L");
            number(sys, cache.level);
            sys.write(switch (cache.kind) {
                abi.cpu_topology_cache_kind_data => "D=",
                abi.cpu_topology_cache_kind_instruction => "I=",
                else => "=",
            });
            bytes(sys, cache.cache_bytes);
        };
        sys.write("\r\n");
    }
}
