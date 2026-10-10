# Local third-party artifacts

This directory intentionally does **not** redistribute device or third-party binaries.

The current LineageOS 18.1 kit builder reads all sources INSIDE this canonical project, rather than depending on a historical sibling crDroid checkout.

| Local source, ignored by Git | Purpose |
|---|---|
| files/installer-assets/lineage18.img.xz | Verified Android 11 non-SAR ROM |
| files/installer-assets/twrp-s55.img | S55-specific TWRP 3.1.1, never S55 Lite |
| files/installer-assets/vendor-s55-known-good.img.zst | Exact repaired, tested vendor read-back |
| files/candidates/NikGapps-core-arm64-11-20260204-signed.zip | Android 11 Google apps |
| files/candidates/s55-2018-compat/ | Hash-pinned legacy MediaTek compatibility helpers |
| backups/device-2026-10-09/boot-active.bin | Verified reference boot image |
| backups/device-2026-10-10/ | Private patch baselines needed by the builder |

These last two paths are relative to the repository root, not to this files directory. Files under backups/device-* are historical/reference inputs. They are NOT radio backups created from a future target phone. Such per-device radio backups are created only during installation under the private-install-state directory, which must never be published.

A fresh public Git clone includes scripts and documentation only. To build a private offline kit, obtain and verify the exact binaries independently, then populate the documented local paths. OEM and Google packages are intentionally never distributed via GitHub.

The old crDroid projects, Android 13 candidate and stock-image collection remain historical research, not prerequisites for this final LineageOS 18.1 builder.

## October 2026 offline ROM/GApps candidate cache

The `files/candidates/` directory is local-only and ignored by Git; binaries are **not redistributed** on GitHub. On Cloud9, these two original signed archives were downloaded directly from the NikGapps project's SourceForge mirror and validated with Python `zipfile.testzip()`:

| OS to test | ZIP file | SHA256 from actual local file |
|---|---|---|
| Android 11 | `candidates/NikGapps-core-arm64-11-20260204-signed.zip` | `a56ad7da66e51a6cd1af0b0fb39a1ac167739161624115276b7f8d00633fd0f8` |
| Android 13 | `candidates/NikGapps-core-arm64-13-20260204-signed.zip` | `d969df417bc3ea9c79e4219c8dd955d8d5f6d31597cbe5f88dc51518a3fc9613` |

These SHA256 fingerprints are locally computed and do not independently authenticate the release signer. **Update October 2026:** NikGapps Core Android 11 **was installed and verified** on our LineageOS 18.1 S55. The Android 13 package has **not** been installed. Never flash Android 13 GApps on an Android 11 ROM or double-install GApps.

Full candidate ranking and next validation gates: [ROM options FR](../docs/ROM-OPTIONS-FR.md) and [ROM options EN](../docs/ROM-OPTIONS-EN.md).
