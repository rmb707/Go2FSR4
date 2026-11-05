# Development validation, November 5, 2026

## Passed

- Windows PowerShell syntax parsing for project scripts and vendored builders.
- Ten automated checks: path containment/ADS rejection; allowed child path;
  release-configuration checks; unexpected baseline/version/hash rejection;
  Secure Boot baseline rejection; uninstall ownership excludes preexisting and
  unrelated packages; tampered file rejection; atomic journal revision retention.
- Five additional lifecycle checks cover exact original INF/device matching,
  required reboot boundaries, another device's rejection, stale-kernel rejection,
  and persistent restore verification. The real verifier is exercised against
  synthetic observations without changing the system.
- Download regression check verifies AMD's required publisher referrer, rejects
  unexpected content despite successful HTTP responses, and rejects HTTP URLs.
  All 20 checks pass, including backup selection for the AMD Windows companion
  whose INF filename changes between driver versions.
- Companion restore checks reject missing, duplicate, unhealthy, or changed
  bindings while accepting the original INF content under a new publishing number.
  The full verifier also rejects a stale companion even when the display driver
  and kernel are correct. Read-only capture on the test device found six unique
  AMD bindings; INF hashing, health checks, and querying a single device passed.
- Kernel security checks reject unavailable/unknown results, Secure Boot off,
  Code Integrity enforcement off, or test signing enabled. The restore verifier
  cannot report completion if current-boot security fails.
- Two additional integration checks: full195-file official AMD package hash
  inventory and existing working candidate (onlyINF/DAT/catalog may differ).
- Preparation from pinned publisher archives, in an isolated temporary sandbox:
  extraction, deterministic builders, original Microsoft kernel-catalog signature
  check, Inf2Cat, companion-catalog restoration, full post-build hash audit, and
  matching AMD Software extraction. No driver/trust/boot mutations performed.
- Native WinForms UI opened; Verify button executed successfully.
- Read-only device verification found32.0.32015.7029, problem0, Secure Boot registry1,
  and the exact expected running kernel hash. It correctly labeled the existing
  manual installation unmanaged. This non-elevated check did not claim a new UEFI
  firmware or Code Integrity verification.
- Isolated COD-library probe selected provider4.1.2* with ID0xF5A5CA1E81001002;
  context creation/destroy returned0. No COD files changed.
- Single EXE built; embedded ZIP integrity/required-entry self-test passed.
- Public benchmark graphic and cropped evidence inspected locally.

## Public package checks, November 5

- Fresh publisher downloads passed for all five pinned assets, including the
  1,782,243,424-byte AMD installer. AMD requires its website as the HTTP referrer;
  otherwise it can return an HTML error page with HTTP 200. Hash verification
  remains mandatory and unchanged.
- Full preparation using those fresh downloads passed: deterministic INF/DAT,
  original Microsoft kernel catalog, generated package catalog, companion catalog
  restoration, complete package inventory, and AMD Software extraction.
- Rechecked the active driver: 32.0.32015.7029, device problem code 0,
  unchanged pinned kernel, and Secure Boot registry enabled after the recorded reboot.
- Current-boot kernel queries succeeded from a standard user session:
  Secure Boot enabled/capable, Code Integrity enforced, test signing disabled,
  Code Integrity flags 0x0000F405. The verifier now requires these direct kernel
  observations in addition to the registry and driver/kernel hashes.
- Repeated the isolated signed-library probe: exact 4.1.2 provider selected;
  D3D12 device creation, context creation, and context destruction succeeded.
- Rebuilt the launcher and passed its embedded-payload self-test.
- Replaced internal handoff notes with public contributor documentation.
- Added a 34-entry source allowlist, private-content checks, archive readback,
  and SHA-256 checksums for both downloads. Local caches, raw reports,
  certificates, logs, and assistant instruction files are excluded.

The non-elevated session cannot query the UEFI variable directly. The kernel
queries independently confirm the active boot's security state. Installation
still requires administrator approval and a direct UEFI check.

## Device setup outcome

- The new AMD driver is running after reboot on the exact Z2 Extreme device,
  with a healthy display device and the unchanged pinned kernel.
- FSR 4.1.2 context creation succeeds with the exact provider selected.
- COD's native FSR 4 benchmark completed on driver 26.10.1. The 800p export
  records 55 base / 109 generated average FPS. The game does not report its exact
  4.x runtime revision, and this is not a claim about future anti-cheat versions.

The original device setup goal is verified. Automated public installation,
uninstallation, and recovery remain separate outstanding release tests below.

## Remaining release checks

- Compiled EXE UAC/elevated extraction/UI workflow on the test machine.
- Automated live install/uninstall, restart persistence, companion binding restore,
  original AMD UI restore, and complete interruption recovery.
- Installer Authenticode publisher signing and public release provenance.

Version 0.1.0 enables installation as an experimental first release. These checks
do not establish that the automated lifecycle or every game's rendering has been
verified. The remaining release checks above are still outstanding.
