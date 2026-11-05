# Go2FSR4 0.1.0 development preview

Not a public install release. Install is intentionally disabled.

Includes a single executable launcher, hardware verification, an isolated FSR
context check, pinned-package preparation, install/uninstall source, protected
transaction-journal design, test suite, and benchmark documentation.

Validated so far: source safety checks, complete official/candidate package
hashes, compiled launcher's embedded-payload check, and read-only driver/kernel
verification on the original test machine.

Still required: live clean install, reboot verification, full uninstall and
post-uninstall reboot, interrupted-operation recovery, fresh-cache publisher
downloads, original AMD UI restoration, installer publisher-signing plan, and
public repository/donation details. See docs/RELEASE-CHECKLIST.md.

Do not distribute this as a finished one-click installer. No promise of support
for other handhelds, all games, or future anti-cheat versions.
