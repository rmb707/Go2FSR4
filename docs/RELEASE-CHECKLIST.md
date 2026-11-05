# Release checklist

The release configuration starts with liveInstallEnabled=false. Do not change it
merely to make the installer appear finished.

## Completed in development

- [x] Exact supported hardware identity and known OEM INF baseline pinned.
- [x] Publisher downloads and all 195 official display-package hashes pinned.
- [x] Deterministic builders retained with their MIT license.
- [x] Existing working package verified against the full pinned manifest.
- [x] Single executable builds; embedded archive self-test passes.
- [x] Read-only verifier detects the working driver and unchanged kernel.
- [x] Automated pure-function/safety checks pass.
- [x] Manual experiment survived reboot with Secure Boot enabled.
- [x] Native COD benchmark exports documented with Ultra Performance mode.

## Required before installation is enabled publicly

- [x] Verify pinned downloads from a fresh cache (not only local files).
- [ ] Run preparation through the actual packaged GUI with publisher tools.
- [ ] Review all source and state transitions, including interrupted operations.
- [ ] Clean known-OEM baseline install on test hardware.
- [ ] Reboot; confirm Secure Boot, Code Integrity, healthy PnP device and running kernel.
- [ ] Matching AMD UI opens after cold boot with original Store registration retained.
- [ ] Run FSR provider check plus native and injected/offline game test.
- [ ] Same executable uninstalls; original display and companion bindings restored.
- [ ] Reboot; confirm original driver and original AMD UI operate.
- [ ] Check only owned certificate/catalog/MSI/packages were removed.
- [ ] Reinstall after completed uninstall without losing old backup/audit records.
- [ ] Simulate download failure, corrupted package, denied UAC, blocked MSI,
      busy package, power interruption, and later-driver replacement.
- [ ] Test offline recovery instructions; retain known-good driver externally.
- [ ] Confirm publisher license/terms for local download and package modification.
- [ ] Decide executable signing and publish independent release hashes/provenance.
- [x] Obtain project owner's Ko-fi URL and GitHub destination.
- [ ] Review README, images, release notes and public support scope.
- [ ] Remove development-only placeholders; set release version/channel deliberately.

## Publishing

Publish source first or a clearly marked developer preview if requested. A binary
whose Install action is disabled is not the promised public one-click installer.
Source publication does not enable installation or establish installer readiness.
