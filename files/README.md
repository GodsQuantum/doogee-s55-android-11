# Local third-party artifacts

This directory intentionally does **not** redistribute device or third-party binaries.

Before using the installation guides, place these files here locally:

```text
files/twrp-3.1.1-doogee-s55.img
files/Disable_Dm-Verity_ForceEncrypt.zip
```

They are ignored by Git and must not be committed.

- TWRP: obtain a Doogee S55-specific recovery image from a source you trust.
- Disable Dm-Verity / ForceEncrypt: upstream project by Zackptg5:
  https://github.com/Zackptg5/Disable_Dm-Verity_ForceEncrypt

Do not substitute an image intended for the S55 Lite or another MediaTek device.

## October 2026 offline ROM/GApps candidate cache

The `files/candidates/` directory is local-only and ignored by Git; binaries are **not redistributed** on GitHub. On Cloud9, these two original signed archives were downloaded directly from the NikGapps project's SourceForge mirror and validated with Python `zipfile.testzip()`:

| OS to test | ZIP file | SHA256 from actual local file |
|---|---|---|
| Android 11 | `candidates/NikGapps-core-arm64-11-20260204-signed.zip` | `a56ad7da66e51a6cd1af0b0fb39a1ac167739161624115276b7f8d00633fd0f8` |
| Android 13 | `candidates/NikGapps-core-arm64-13-20260204-signed.zip` | `d969df417bc3ea9c79e4219c8dd955d8d5f6d31597cbe5f88dc51518a3fc9613` |

These SHA256 fingerprints are locally computed and do not independently authenticate the release signer. **Update October 2026:** NikGapps Core Android 11 **was installed and verified** on our LineageOS 18.1 S55. The Android 13 package has **not** been installed. Never flash Android 13 GApps on an Android 11 ROM or double-install GApps.

Full candidate ranking and next validation gates: [ROM options FR](../docs/ROM-OPTIONS-FR.md) and [ROM options EN](../docs/ROM-OPTIONS-EN.md).
