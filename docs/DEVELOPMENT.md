# Development

## Build

Use Windows PowerShell 5.1 on Windows x64 with the .NET Framework C# compiler.

```powershell
./tests/Test.ps1
./tools/Build.ps1
./tools/Package.ps1
```

The build creates a single launcher with an embedded source/configuration bundle.
Its self-test checks bundle integrity and required entries without installing a
driver. Packaging creates a source ZIP from an explicit public file list and
updates SHA256SUMS.txt for both downloads.

Optional publisher integration checks:

```powershell
./tools/Test-Downloads.ps1
./tools/Test-Preparation.ps1 -SeedDirectory <fresh-cache-path>
```

The first command prints the new cache path and verifies all pinned downloads.
The second prepares a package in an isolated temporary directory using those
archives, without installing drivers, certificates, or AMD Software.

## Source layout

- `src/`: launcher, user interface, driver lifecycle, and isolated FSR probe.
- `config/`: supported hardware, pinned downloads, and original-file hashes.
- `vendor/`: attributed deterministic package builders and their license.
- `tests/`: parser and safety checks; optional package integration checks.
- `tools/`: build, packaging, preparation tests, and benchmark chart generation.
- `docs/`: results, security design, and release validation.

Publisher binaries, local caches, certificates, recovery logs, raw benchmark
exports, and internal assistant files are excluded from public packages.

## Release validation

The current channel is development and live installation is disabled. Packaging
does not change that setting. Read-only device checks and an FSR context probe do
not validate a complete automated install/uninstall lifecycle.

Before enabling installation, complete the [release checklist](RELEASE-CHECKLIST.md)
and record results in [validation status](VALIDATION.md). Test installation from
the supported Lenovo baseline, reboot persistence, AMD Settings, restore,
reinstallation, and interrupted-operation recovery. Use a clean supported starting
state; the installer does not adopt unrelated manual driver modifications.

Keep the README short: confirmed data and installation guidance only. COD runs
use native FSR 4 Ultra Performance. Technical development detail belongs here.
