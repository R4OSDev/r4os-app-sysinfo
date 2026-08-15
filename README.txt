SYSINFO.R4X
===========

SYSINFO.R4X zeigt System-, Kernel-, Netzwerk- und Laufzeitinformationen im
Terminal.

Projektstruktur seit 0.51.18:
- `build.zig` baut die App als eigenes SDK-Projekt.
- `build.zig.zon` bindet `r4os_sdk` als Paket.
- `module.R4MF` beschreibt Artefakt, Zielpfad und Contract.

Build:

    cd Code\System\Software\SysInfo
    ..\..\..\DevTools\Zig\zig.exe build

Ergebnis:

    Code\System\Software\SysInfo\zig-out\SYSINFO.R4X

Contract:
- R4XStart-Entry: `sysinfo_main`
- App-Klasse: `console`
- R4L-Imports: `R4DEV:Query:1`, `R4NET:Query:1`
- Zielpfad im Image: `C:\R4OS\SOFTWARE\TERMINAL\SYSINFO.R4X`

