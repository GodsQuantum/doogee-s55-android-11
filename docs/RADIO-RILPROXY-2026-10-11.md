# DOOGEE S55 — MediaTek RIL crash and offline-only candidate

**11 October 2026, updated after live experiments.** The native PHH auto-restart workaround is REJECTED. The callback-guard candidate passed offline tests and was TEMPORARILY loaded twice on the real S55, followed each time by verified restoration of the OEM library. It is NOT installed persistently. The reference S55 has NO SIM; calls/SMS/data remain unvalidated.

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

## Physical S55 reversible proof — 11 October 2026

**Actual runtime bind-mount test PASS (restricted scope):** after the owner enabled rooted debugging, a private SHA256-pinned candidate was staged on a temporary /dev tmpfs file labelled vendor_file. The original /vendor partition remained ext4 read-only and SELinux stayed Enforcing. A single-file bind mount over /vendor/lib64/librilproxy.so showed the candidate hash. After controlled init restart, rilproxy PID 4745 successfully loaded the candidate executable mapping, remained the SAME running PID for 32 seconds in 7 checks, and exposed HIDL IRadio slot1 and slot2. No new radio native crash was found in the crash log. Both SIM trays were empty. **This validates load/startup, not networkInfoInd's null fault path or any voice/SMS/data operation**.

The initial trap unmount failed with Device or resource busy because the RIL process still mapped the library. Recovery was immediately executed in the correct order: init STOP ril-proxy, wait for the old PID to leave, UNMOUNT only the single-file bind mount, verify the vendor original SHA256, init START ril-proxy. RIL was running, vendor returned to the original hash, and SELinux remained Enforcing. All temporary staging files were removed. Nothing persistent was installed on Android.

**New reusable safe test harness:** scripts/trial-rilproxy-live.sh, host-side --check, --trial <private-candidate.so> [5..180 seconds], and --recover. It pins actual S55 identity, OEM/candidate SHA256, SELinux Enforcing and restart_ril disabled. Normal completion and non-success cases stop the RIL process BEFORE unmount, restore original SHA256 and relaunch it, then return adbd to non-root. The bind mount is memory-only; a device reboot also clears it. The harness MUST NOT modify vendor partitions or be called as part of unattended installation. User must run physical voice/SMS/data tests with a SIM separately before claiming full cellular recovery.

Follow-up real S55 harness regression: --check recognized the OEM SHA256 and a running radio service; --trial loaded the candidate for 10 seconds with stable PID and ELF mapping, followed by automatic output ORIGINAL_RIL_RESTORED. Independent non-root ADB then verified OEM SHA256 restored, service running, PHH restart_ril=false and SELinux Enforcing. The --recover action remains available for interrupted trials. Both trials were time-bounded and no persistent radio code was changed.


## Production decision and rollback

**DO NOT INSTALL THE CANDIDATE IN THE STANDARD ONE-COMMAND KIT YET** and do not replace the golden vendor. The bind-mount startup and rollback smoke test has now passed on the real phone after rooted debugging was enabled. However, testing the actual original crash trigger, cellular voice, SMS, data, standby and multi-reboot stability is still required BEFORE installing a persistent vendor patch.

Leave persist.sys.phh.restart_ril=false; keep SELinux Enforcing and untouched boot, modem, firmware, unique radio calibration and battery undervoltage protections. Do not blindly add a radio restart loop, disable calls or flash firmware from an unrelated handset. This project does not currently warrant claiming fully repaired cellular functionality.
