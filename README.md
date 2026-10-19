# SYSINFO.R4X

`SYSINFO.R4X` is an independent R4OS application implemented in Zig.

## Package

- Version: `0.1.11`
- Image target: `/R4OS/SOFTWARE/TERMINAL/SYSINFO.R4X`
- Image scope: `full`
- Canonical project manifest: `module.R4MF`

The manifest is the single source of truth for the artifact, imports, image
target, and package metadata.

`SYSINFO /CPUIDLE:<cpu>` passively reads the independent idle declaration,
eligibility/rejection reason and software attempts/fallback counters. ACPI
latency and power values are declared properties. Hardware residency, wake
latency and energy remain explicitly unavailable without their own readback.
The query never forces a CPU into a power state.
The display uses source-specific declarations: `_CST` supplies no minimum
residency property, `_LPI` supplies no declared power value, and missing or
invalid declarations are printed as unavailable.

## Build

On Windows:

    Build.bat

On Linux or macOS:

    ./Build.sh

The build starters resolve the current local R4OS dependency checkouts through
`Settings.R4S`. The URL and hash entries in `build.zig.zon` record the
last verified standalone dependency identities; workspace builds use the
mapped local checkouts.

## Documentation

Detailed German technical notes from the migration are preserved in
`DOCUMENTATION.de.txt`. Source-transfer provenance is recorded in
`PROVENANCE.txt`.

## License

Original R4OS material is licensed under Apache License 2.0. See `LICENSE`
and `NOTICE`. Any repository-specific external material is documented in
`THIRD_PARTY_NOTICES.md`.
