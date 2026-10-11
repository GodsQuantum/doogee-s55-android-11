<p align="center"><img src="docs/assets/logo.svg" width="136" alt="DOOGEE S55 系统升级项目标志"></p>

<h1 align="center">DOOGEE S55 · LineageOS 18.1</h1>

<p align="center"><strong>让三防手机焕发新生：Android 11、Google Play 与硬件兼容修复。</strong><br>
离线安装包 · 单命令引导安装 · 完整校验 · 私有备份</p>

<p align="center">
  <a href="https://github.com/GodsQuantum/doogee-s55-android-11/actions/workflows/lint.yml"><img src="https://github.com/GodsQuantum/doogee-s55-android-11/actions/workflows/lint.yml/badge.svg" alt="代码检查"></a>
  <img src="https://img.shields.io/badge/Android-11%20%7C%20LineageOS%2018.1-3dd7cf" alt="Android 11">
  <img src="https://img.shields.io/badge/机型-DOOGEE%20S55-18283b" alt="仅适用于 S55">
  <a href="LICENSE"><img src="https://img.shields.io/badge/许可-MIT-3dd7cf" alt="MIT 许可证"></a>
</p>

<p align="center"><a href="README.md">English</a> · <a href="README.fr.md">Français</a> · <strong>简体中文</strong></p>

---

## 🚀 一条命令安装

将准备好的离线 **`local-kit/` 文件夹**整体复制到连接 **原厂 DOOGEE S55（Android 8）** 的 Linux 电脑上，然后执行：

```bash
cd local-kit
./INSTALL.sh
```

脚本自动校验 ROM、TWRP、Google 应用和固件文件的 SHA256；核对机型与分区表；引导解锁 Bootloader、进入 TWRP；备份原始系统和设备专属的无线电校准数据；调整已知 S55 的系统分区；安装 LineageOS 18.1 + NikGapps Core、硬件兼容修复；最后验证 Android 启动情况。

**GitHub 仓库不包含专有固件、Google 安装包和手机个人备份。** 维护者必须先获得准确校验过的二进制文件，在已有项目工作目录中生成离线包：

```bash
bash scripts/build-s55-lineage18-kit.sh
```

主机需要 ADB、Fastboot、Python 3、xz、zstd。pv 可选；安装包内置 Python 刷写进度显示。**请以普通用户运行，不要使用 `sudo`**。

**安装前必须：**自行备份照片及文件、确保电量**至少 40%**，在 Android 8 中打开 USB 调试及 OEM 解锁。**该安装会清除应用及全部内部存储数据。** Bootloader 解锁可能需要在手机上确认，进入 Recovery 也可能需要实体按键操作。

[**完整 A–Z 安装说明（英文）→**](installer/README.md) · [**安全审计与恢复限制**](docs/INSTALLER-SAFETY-AUDIT-2026-10.md)

**电池与性能优化：** [原生设置、真实测试与限制](docs/POWER-PERFORMANCE-2026-10.md)。

仅进行只读检查，不写入手机（--verify 用于已启动 Android 11 的 S55；切勿为复查而重新刷机）：

```bash
./INSTALL.sh --plan
./INSTALL.sh --check
./INSTALL.sh --verify
./INSTALL.sh --recovery-check
```

--recovery-check 在本地校验原始 GPT 与九份分区备份，不会写入任何分区。

## ✨ 已验证的改进

| 项目 | 参考 S55 上的验证结果 |
|---|---|
| **Android 系统** | LineageOS 18.1 / Android 11 正常开机并可重启 |
| **Google 服务** | NikGapps Core、Play 商店、GMS 和 GSF 已安装 |
| **指纹 MicroArray** | **已在参考 S55 上实测成功**：MicroArray 补丁与 PHH 保留机制配合使用，重启后指纹仍能解锁 |
| **电池读数** | Android 能获得真实电压与温度，不使用虚假固定数值 |
| **热管理** | CPU、GPU、电池、机身温度正常上报，SELinux 保持 **Enforcing** |
| **传感器与手势** | 适配旧版 MediaTek 供应商库 |
| **续航设置** | 电量降至 25% 自动启用 Android 原生省电模式 |
| **用户数据** | 修复 Android 11 下的数据分区与 vendor CE/DE 初始化 |

## 🛡️ 安全与限制

- **仅适用于标准 DOOGEE S55，不适用于 S55 Lite。** Android 13 及更新的 GSI 不能直接刷入该非 SAR / Oreo vendor 设备。
- 在分区或刷机前备份原设备的 `system`、`boot`、`recovery`、`vendor`、`nvram`、`nvdata`、保护分区及 GPT。设备专属校准数据绝不会分享。
- **电池读数已修复，但深度放电后的恢复仍未验证。** 关机充电、电池老化和电量估算需单独检查。保留 25% 自动省电设置，建议在约 20% 时充电，不要故意放电至 0%。10 月 11 日还发现 MediaTek 无线电服务反复崩溃，使用 SIM 前应另行验证。离线安装包包含只读诊断 scripts/diagnose-battery.sh。PHH 自动重启 RIL 导致启动循环，现已禁用。2026 年 10 月 11 日，MediaTek RIL 单字节修复已永久安装到真实 DOOGEE S55 的 vendor 分区；两次 Android 重启后仍有效，RIL 服务、两个 HIDL 无线电接口、指纹和 SELinux Enforcing 正常，观察期间未出现新的原生崩溃。离线安装包的 vendor 镜像仍为原版，重装会撤销修复。没有 SIM 卡，电话、短信和移动数据仍未验证：docs/RADIO-RILPROXY-2026-10-11.md。
- **2026 年 10 月 10 日机主确认：参考 S55 重启后可使用已登记指纹解锁。** 离线安装包包含 MicroArray 驱动修复与 PHH 指纹保留设置。其他 S55 仍须在安装后自行登记指纹、重启并测试解锁；自动检查只能验证配置，无法代替真人指纹测试。
- 所有文件已通过离线校验和只读预检；**尚未在第二台从未修改的原厂 S55 上完成全部刷机流程**。未知硬件版本会拒绝安装。

## 📚 文档与技术资料

- [单命令完整安装说明（英文）](installer/README.md)
- [LineageOS 18.1 初次启动修复](docs/LINEAGE18-MIGRATION-ROOT-CAUSE-2026-10.md)
- [电池温度、热管理与省电设置](docs/BATTERY-THERMAL-LINEAGE18-2026-10.md)
- [MicroArray 指纹修复](docs/FINGERPRINT-FIX.md)
- [ROM 兼容性与 Android 13 研究](docs/ROM-OPTIONS-EN.md)
- [旧版 crDroid 安装指南存档](docs/CRDROID-LEGACY.md)
- [安全政策](SECURITY.md)

## 🧰 开发与贡献

```bash
make lint
bash scripts/build-s55-lineage18-kit.sh
```

本项目为独立社区项目，**与 DOOGEE、LineageOS、NikGapps 官方无关联**。专有镜像、第三方安装包以及 IMEI/NVRAM 等设备私人数据不会提交到公共 GitHub 仓库。

[贡献指南](CONTRIBUTING.md) · [第三方声明](THIRD_PARTY_NOTICES.md) · [MIT 许可证](LICENSE)
