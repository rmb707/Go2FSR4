# Go2FSR4 v0.1.0 — experimental first release

Installation is enabled. This is the first public package.

## Install

Download **Go2FSR4.exe**, run it as administrator, choose **Install**, and restart.
Reopen the same app and choose **Verify**. Use **Uninstall** in that app to restore
the driver backed up by its installation.

Supported starting point: Legion Go 2 Z2 Extreme / Radeon 890M, exact C5 device
profile, Windows 11, Lenovo driver **32.0.23033.5002**. Internet and **12 GB free**
are required. The AMD package is downloaded directly from AMD and checked by hash.

## Included

- AMD Adrenalin **26.10.1** adaptation with Secure Boot kept enabled.
- Matching AMD Settings and DVR packages.
- Hardware/security checks, verified downloads, driver backups, and recovery journal.
- Isolated exact **FSR 4.1.2** context check without modifying games.

## Validation status

The driver setup and native COD benchmark were tested on the original device.
Source checks, package hashes, fresh downloads, preparation, and launcher bundle
verification pass. **The automated clean-install/reboot/uninstall/reinstall cycle
and interruption recovery have not completed live validation.** Existing manual
installations are not adopted.

The executable is unsigned. **SHA256SUMS.txt** lists the executable and source ZIP
hashes. This experimental release does not claim publisher signing or universal
game compatibility.
