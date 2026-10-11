# DOOGEE S55 — MediaTek RIL crash and offline-only candidate

**11 October 2026.** The native PHH automatic restart workaround is REJECTED. An ELF callback-guard candidate has passed offline tests but HAS NOT BEEN APPLIED TO THE PHONE. The reference S55 has NO SIM, so calls/SMS/data are not validated.

## Confirmed live facts
- Android 11 LineageOS 18.1 with DOOGEE/S55/S55 Oreo vendor.
- Native rilproxy SIGSEGV (null address) in radio::networkInfoInd at librilproxy.so virtual 0x5bb4c (function +272). Previous identical historical crashes and 131 Android com.android.phone process deaths were seen, but the 131 process deaths are not 131 unique native RIL crashes.
- Independent report on a different MediaTek Oreo vendor under LineageOS recorded the same crash function: https://forum.shiftphones.com/threads/lineageos-15-1-android-8-1.1950/page-2
- Manual one-time start of stopped ril-proxy returned the service to running and exposed Android hardware radio HIDL endpoints. This alone does not prove SIM reliability.
- Enabling persist.sys.phh.restart_ril=true let Android restart ril-proxy after a deliberate stop, BUT a subsequent normal reboot caused repeated Android/preloader USB transitions. The property was immediately changed to false. Android then reached sys.boot_completed=1, retained the fingerprint and had a running RIL. This native PHH toggle MUST NOT be used on S55.

## Root cause candidate from exact OEM ARM64 ELF

Original /vendor/lib64/librilproxy.so SHA256:
425312124514d3b87e0d8f249bb92596a2b90e6212c9484b524e761227f15f07

Inside radio::networkInfoInd:
- 0x5ba98 loads the radio service pointer, guarded at 0x5ba9c.
- 0x5baa0 loads the RESPONSE callback at offset +0x18, guarded by a branch at 0x5baa4.
- 0x5bb48 later loads the INDICATION callback at offset +0x28.
- 0x5bb4c dereferences that callback without a null check. This is the observed SIGSEGV when it is missing.

The offline test patch uses the existing early null branch to guard the indication callback (the object actually used): replace at ELF offset 0x56aa0 the ARM64 instruction bytes 08 0d 40 f9 with 08 15 40 f9. The branch remains intact and returns before allocation if callback null. **This changes exactly one instruction byte**, no other binary offsets or data. Result SHA256:
f47a4248174b4f375d82ccf1a83fc5bb4bcdea0d8594a7904195a37f4b9ac4f0

Only the SHA256-pinned original ELF is accepted by scripts/patch-rilproxy-networkinfo.py. Development and objdump verification took place on LXC 700. Synthetic tests prove unexpected versions/offsets are rejected, the branch target is unchanged and only one byte changes. They do NOT prove live RIL behavior or telephone call compatibility. Proprietary ELF is excluded from public Git.

## Production decision and rollback

**DO NOT INSTALL THE CANDIDATE IN THE STANDARD ONE-COMMAND KIT YET** and do not replace the golden vendor. A reversible live mount with full rollback, SIM testing and standby logging is required first. Following the post-boot test, ADB rooted debugging was disabled by phone settings, so no safe root test could be performed at this checkpoint without changing that security setting or entering recovery.

Leave persist.sys.phh.restart_ril=false; keep SELinux Enforcing and untouched boot, modem, firmware, unique radio calibration and battery undervoltage protections. Do not blindly add a radio restart loop, disable calls or flash firmware from an unrelated handset. This project does not currently warrant claiming fully repaired cellular functionality.
