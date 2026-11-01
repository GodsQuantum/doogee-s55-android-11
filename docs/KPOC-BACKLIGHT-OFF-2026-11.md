# DOOGEE S55 — KPOC off-mode backlight shutdown (v10, 2026-11-01)

**Physical status: PASS on the reference handset (one test).** With Android powered off and USB inserted, the personalized portrait logo appeared, then the LCD backlight became completely dark for more than 20 seconds. The owner subsequently booted Android normally. This proves the visible LCD outcome on this handset, not net charging current or support for other S55 hardware revisions. The immediately preceding boot's kernel log remains pending.

## Previous failures and the final change

MediaTek KPOC (USB ID 0e8d:2008) is a separate boot mode; it does not simply reuse Android's last brightness. Earlier code produced an all-black framebuffer while leaving the LCD lit. v7 repeatedly requested backlight brightness 0; v8 serialized charger-class LED helper startup after bridge exit. Neither fixed the physical backlight. The likely underlying issue is the MediaTek 3.18 PWM driver caching a zero request even while the physical PWM remains active. This mechanism is supported by driver code but not independently established on this exact handset without a boot log.

**v10 introduced a real level 1-to-0 transition**, in the existing KPOC-only helper, with bounded timings and a zero readback. Code: [LCD helper](../scripts/kpoc-s55-lcd-off.c). For each of three existing attempts: write brightness 1, wait 90 ms, write brightness 0, wait 35 ms, read back 0; two inter-attempt delays remain 450 and 650 ms. There is no daemon, polling loop or global Android brightness adjustment.

Service control remains in [bridge init](../scripts/s55-kpoc-bridge.rc) and [LED init](../scripts/s55-kpoc-lcd-off.rc). The LED helper executes in OEM mtk_hal_light context; SELinux allows writes to the backlight sysfs node but **not** to /dev/kmsg. The existing framebuffer helper executes in charger context, which permits /dev/kmsg; v9 therefore instruments only that helper: [FB ioctl and LED diagnostics](../scripts/kpoc-s55-fb-off.c). It reads brightness before and after FBIOBLANK(4), logs its syscall result, and does not modify charging or brightness. Note: the MediaTek mtkfb_blank_suspend path can skip hardware panel suspend when the display stage is not normal, so framebuffer-black alone is insufficient evidence.

## Reproducing the build safely

Use Clang/LLD for static AArch64 ELF, -Os -static -fno-stack-protector -fno-builtin -ffreestanding -nostdlib -fuse-ld=lld -Wl,-e,_start -Wl,--build-id=none -Wall -Wextra -Werror, and target aarch64-linux-gnu. Compile the C helpers separately. The v10 reference helper SHA256 is **95204eca3be544e0965a1a0d7b12977352e70cb7064be7b1f73ab949fa5be77b**, which identifies one specific build, not all compatible firmware.

Never flash the output blindly: compare the device and current vendor binary hashes, establish root ADB, preserve SELinux Enforcing, make rollback backups, verify the executable's context, and restore /vendor read-only. The device-specific private installers did this and confirmed both helper installation readbacks. No kernel, boot, LK/preloader, PMIC, charge-current, autosleep or CPU-suspend configuration was changed. Proprietary OEM images, personal artwork and backups remain excluded from Git.

## Custom charging logo

The original MTK 8 MiB logo partition contains **39 compressed sprites**. [Generic artwork converter](../scripts/patch-s55-logo-artwork.py) checks a source PNG digest and known-good OEM partition, crops a **full-height 1:2 portrait** section, bilinearly scales to **720 × 1440**, then changes **only sprite index 2**. The other 38 OEM images, notably the warning sprite, remain unmodified. The earlier square-centered composition was physically rejected; the final portrait composition passed. The design makes no false battery percentage claims. All real battery readings remain managed by native fuel-gauge services.

## Evidence and limits

| Check | Status |
|---|---|
| USB off-mode starts, personalized logo appears | PASS — owner observation 2026-11-01 |
| LCD becomes physically dark and stays dark >20 seconds | PASS — owner observation 2026-11-01 |
| Android subsequently boots with SELinux Enforcing | PASS — independent ADB read-only check |
| v9+v10 installer SHA/readback and vendor remount RO | PASS — user-provided on-device installer output |
| Battery snapshot after boot | 100%, 4,257 mV, 29 °C; not a charge-gain measurement |
| Early KPOC kernel previous-boot log and PWM telemetry | PENDING (ADB root access needed) |
| Net charging and extended stability | NOT CERTIFIED |
| Other S55 batches and S55 Lite | NOT TESTED (never apply to S55 Lite) |

**Safety:** retain original logo, LED and framebuffer helper backups and rollback scripts. Do not try a /sys/power/autosleep workaround without a validated wakeup/USB/power-key lifecycle. The KPOC patch only addresses display illumination, and neither protects against physical deep discharge nor establishes net charge gain.

## Earlier investigations and upstream

- [Suspend and display analysis](KPOC-SUSPEND-ROOT-CAUSE-2026-10-30.md)
- [OEM display and charger research](KPOC-ORIGINAL-POWER-DISPLAY-RESEARCH-2026-10-30.md)
- [Fuel-gauge findings](KPOC-LAST-KMSG-FUELGAUGE-2026-10-30.md)
- [MediaTek 3.18 LED driver](https://android.googlesource.com/kernel/mediatek/+/android-mtk-3.18/drivers/misc/mediatek/leds/leds_drv.c)
- [Android 11 init behavior](https://android.googlesource.com/platform/system/core/+/refs/heads/android11-release/init/README.md)
