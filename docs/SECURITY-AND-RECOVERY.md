# Security and recovery design

## Trust boundaries

The launcher is a normal user process until it requests UAC elevation. It validates
its embedded bundle before extraction. Extracted files go under Program Files;
existing directories must have trusted ownership and no untrusted write grants.
Path traversal, alternate data streams, and reparse-point ancestors are rejected.
Machine transaction state is held in an administrator/SYSTEM-only ProgramData
folder. Checksums are pinned in the embedded configuration. Checksums are not a
substitute for an authenticated executable publisher.

Downloads are HTTPS and SHA-256 pinned. The entire 195-file official display
package is checked. After adaptation, only INF, DAT, and the local catalog may
differ. The original Microsoft catalog is used to check the unchanged kernel
before installation. No package installer is run merely to unpack it.

The isolated FSR probe checks AMD signatures, copies libraries to a fresh folder,
and selects exactly 4.1.2 or 4.1.2 *. It does not write to game directories.

Read-only verification queries the current Windows kernel for Secure Boot and
Code Integrity state through `NtQuerySystemInformation` classes 145 and 103.
Successful query status and expected structure lengths are required; unavailable
data is not treated as proof. These queries succeeded without elevation on the
test device. Installation still requires administrator approval and
`Confirm-SecureBootUEFI`; no privilege elevation or boot-policy change is used
to obtain the read-only report.

## Transaction journal

Write a verified backup and baseline inventory before importing trust or installing
packages. Atomic replacement keeps the previous journal revision. Record a
certificate thumbprint and MSI intent before corresponding installation actions.
Record exact candidate INF hashes so recovery can identify companions even if
execution was interrupted before the inventory-after write.

Schema 2 records the affected devices' original INF hashes and health before
installation. Every recorded binding must have an INF in the verified backup.
Versioned `amdwin-u*.inf` filenames are treated as the same companion family for
backup selection, while unrelated driver families remain excluded.

Uninstall is fail-closed: restore the original display binding first; remove only
new packages in the candidate hash set; restore original companions; remove owned
MSIs; remove the explicitly named registered catalog and exact certificate. No
wildcard driver deletion or generic AMD cleanup tool is used.

Backups are retained. A busy package produces recovery-required status, not a
false success. A later unrelated display version stops automatic rollback.

Restore checks require the original hardware identity, driver version, pinned
Lenovo INF hash, healthy device, and Secure Boot. Completion also requires a later
boot with the running kernel matching the saved original kernel hash and every
recorded companion device healthy on its original INF content. INF publishing
numbers may change during restore; content hashes must match. Cleanup retains
certificate trust and requests recovery if an original binding is missing,
unhealthy, or still using another package. A completed
restore remains verifiable when the app is opened again; the UI distinguishes it
from verification of the new FSR driver.

## Limits requiring release validation

- Live end-to-end lifecycle and forced-interruption tests have not run.
- Companion-driver rollback and active device bindings must be checked after reboot.
- Catalog registration/removal behavior needs live confirmation, including retries.
- Existing manually modified drivers and native AMD Software migrations are blocked.
- The test device already has an unmanaged experimental installation. Its complete
  migration/cleanup must be planned separately; it must not be falsely adopted.
- The Store-app coexistence strategy needs cold-boot testing; the manual experiment
  removed the old Store app, whereas the reusable installer retains registration.
- Managed reinstallation after a completed uninstall needs validation.
- Reboots are user-triggered; no automatic resume task has been implemented.
- Verification reads driver health and kernel hashes; it cannot promise every game,
  future anti-cheat policy, thermal limit, firmware version, or visual outcome.
- Public installer Authenticode signing and provenance are not complete.
- Downloads can be replaced by publishers: pinned hashes deliberately stop execution.
- Application logs are not automatically collected or uploaded.

## Recovery outside Windows

Do not publish a one-click recovery claim until the documented Windows Recovery /
Safe Mode procedure has been tested with the exported Lenovo driver. Keep recovery
material on a separate drive before live release validation. Do not advise users
to disable Secure Boot or normal integrity enforcement to complete installation.
