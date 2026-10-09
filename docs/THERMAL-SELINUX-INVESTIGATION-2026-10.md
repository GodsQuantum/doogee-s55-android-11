# DOOGEE S55 — thermal HAL and proc_mtktz SELinux audit (10 October 2026)

**State: exact policy gap found; a minimal correction compiles offline but has NOT been flashed or installed.** Device still uses enforcing SELinux. This document is intentionally separate from validated repairs in [ROOT-CAUSE-HEALTHD-VENDOR-2026-10.md](ROOT-CAUSE-HEALTHD-VENDOR-2026-10.md).

## What the device exposes

TWRP 3.1.1 root, Linux 3.18.60+ kernel from 2018:
- `/proc/mtktz/mtktsbattery` returned **25000** (25°C), `mtktscpu` returned ~37200–38000 (37.2–38°C).
- `/sys/class/thermal/thermal_zone0/type` = `mtktsbattery`, and its `temp` value returned 29000 (29°C) during a separate read. Different times/paths were observed; do not assume all represent the same calibrated sensor.
- `/sys/class/power_supply/battery/batt_temp` returned **0 even as recovery root**, so the Android battery field is **not repaired** by adjusting SELinux alone.
- Under Android 11 + SELinux enforcing, unprivileged ADB shell gets **Permission denied** reading `/proc/mtktz/mtktsbattery` and `thermal_zone0/temp`. `thermal-hal-1-0` logs `EACCES(-13)` for its /proc/mtktz access.
- The vendor init service runs `/vendor/bin/hw/android.hardware.thermal@1.0-service` under user **system**, group **system**, domain `hal_thermal_default`. Android's `dumpsys thermalservice` connects to ThermalHAL 1.0 but obtains **no usable temperatures**.

## Concrete policy gap

The **actual backed-up vendor `/vendor/etc/selinux/nonplat_sepolicy.cil`** has:
- `(type proc_mtktz)`, `(genfscon proc /mtktz (u object_r proc_mtktz ((s0) (s0))))`.
- Read policies for `system_server_26_0`, `thermal_manager`, camera, media codecs and other legacy MediaTek domains.
- **No** allow rule from `hal_thermal_default` to `proc_mtktz`, although this is the service that opens the proc entries.

Upstream MediaTek Android 11 device sepolicy likewise contains [read rules for proc_mtktz](https://android.googlesource.com/device/mediatek/wembley-sepolicy/+/refs/tags/android-11.0.0_r44/r_non_plat/system_server.te). This corroborates that procfs access requires an explicit policy grant.

A minimal **read-only** candidate is:

```cil
(allow hal_thermal_default proc_mtktz (dir (search read open getattr)))
(allow hal_thermal_default proc_mtktz (file (open read getattr)))
```

No write, ioctl, relabel, execute, root or permissive capability is authorized.

## Reproducible **offline** test — not a live fix

Extracted the exact active Android 11 GSI's `/etc/selinux/plat_sepolicy.cil`, `/etc/selinux/mapping/26.0.cil`, `26.0.compat.cil`, and the exact device vendor's `nonplat_sepolicy.cil`. Both original and policy-with-the-two-read-rules compiled using Debian secilc 3.8.1, `-m -M true -N -G -c 30`, with distinct binary hashes.

**Caveat:** The **unmodified original** Oreo vendor policy already trips `neverallow` conflicts with the Android 11 platform when the current desktop compiler is run without `-N`. Therefore successful compilation with `-N` is **not an end-to-end boot or security validation**. The device may preferentially load the vendor's precompiled policy based on hashes rather than the modified text policy.

**Do not copy the offline compiled binary into the smartphone.** A complete runtime-loading analysis, an exact original binary policy backup, security review and recovery-verified rollback are needed before a live attempt. Do not set SELinux to Permissive globally. Keep camera, calls, modem, fingerprint and thermal safety behavior intact.

## Priority of next tests

1. Capture exact thermal HAL denial in a privileged kernel audit trace where available. Determine if procfs access is due exclusively to `proc_mtktz` SELinux denial or also Linux DAC/open flags.
2. Build and test a narrow vendor sepolicy extension against the **device's actual loaded policy**; preserve and verify the entire boot/recovery path first.
3. Confirm both CPU/battery zones in Android `dumpsys thermalservice` under Enforcing and validate independent thermometer/battery charging protections.
4. Separately investigate why MediaTek's kernel `batt_temp` reads zero and whether the source from `mtktsbattery` can be bridged with correct millidegree → tenths-of-degree conversion inside a supported health HAL. Never spoof a fixed safe temperature.

The fact that some policy rules are missing does **not** show that blanket root access should be granted. More privileges would not correct `batt_temp=0` nor outdated linker ABI automatically.
