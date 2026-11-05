# Go2FSR4 third-party notices

Deterministic INF and DAT builders in vendor/ are copied from the MIT-licensed
ryanoceros94/LeGo2-Adrenalin26.10.1 public-beta-v5.0.1 toolkit. Their original
license is included in vendor/LICENSE-LeGo2.txt. Only these pure package builders
are used; the upstream boot-policy-changing installation workflow is not included.
Source: https://github.com/ryanoceros94/LeGo2-Adrenalin26.10.1

The Ally2Deck-v3 project informed the investigation of unchanged Microsoft-signed
kernel binaries with locally signed package metadata. No code from that project
is included (no license was identified during this audit).
Source: https://github.com/steminvader/Ally2Deck-v3

AMD driver/software binaries are NOT included in source or the launcher. Downloads
come from AMD, are pinned by SHA-256, and remain subject to AMD's terms. This
project does not grant redistribution rights to AMD binaries or brand assets.

Microsoft SDK/WDK tools and 7-Zip are downloaded from their publishers and used
locally. Their licenses remain with the downloaded packages. They are not bundled
in the launcher. No private signing keys are distributed.

The FSR context probe uses the publicly documented FidelityFX API. It requires
user-supplied AMD-signed loader/upscaler DLLs; it never modifies a game directory.
