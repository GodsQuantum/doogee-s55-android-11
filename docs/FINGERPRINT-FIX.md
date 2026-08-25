# Doogee S55 MicroArray fingerprint fix

[← README](../README.md) · [Technical notes](TECHNICAL-NOTES.md) · [`fix-microarray-fingerprint.sh`](../scripts/fix-microarray-fingerprint.sh)

## Français

### Symptôme

Sous crDroid 7.16 / Android 11 sur le S55 :

- l'enregistrement d'une empreinte fonctionne au premier setup ;
- après le premier reboot, l'authentification par empreinte ne répond plus ;
- ajouter une nouvelle empreinte échoue également ;
- le capteur physique continue pourtant de répondre en mode navigation ;
- le HAL ne crash pas.

Les logs Android montrent que les nouveaux clients `AuthenticationClientImpl` / `EnrollClientImpl` sont bloqués par :

```text
Internal cleanup in progress
```

### Pourquoi le workaround PHH `nocleanup` ne suffit pas

`persist.sys.phh.fingerprint.nocleanup=true` est un workaround GSI connu et pertinent sur certains appareils. Il a été testé proprement sur ce S55 et **ne résout pas la panne**.

L'analyse du `services.jar` Android 11 montre que cette propriété agit dans `InternalEnumerateClient.doTemplateCleanup()` pour empêcher la suppression de templates logiciels inconnus. Elle **ne court-circuite pas l'énumération** elle-même. Le client reste donc bloqué si le HAL ne termine jamais correctement l'énumération.

### Cause exacte validée sur ce S55

Le wrapper `/vendor/lib64/hw/microarray.fingerprint.default.so` importe `bio_enumerate` depuis :

```text
/vendor/lib64/libfprint-x64.so
```

Dans le binaire testé, `bio_enumerate()` appelle `ma_tac_enumerate`, puis appelle `enumerate_notify`. L'ancienne implémentation transmet une valeur non terminale comme `remaining_templates` lorsqu'un template existe.

Or le contrat Android fingerprint indique que `remaining_templates` est **le nombre d'autres messages d'énumération encore attendus**. La séquence terminale doit donc atteindre `0`. Android 11 ne libère `InternalEnumerateClient` qu'à cette condition.

C'est pourquoi le bug apparaît typiquement **après avoir enregistré une empreinte puis rebooté**.

### Patch validé

Bibliothèque :

```text
/vendor/lib64/libfprint-x64.so
```

Original :

```text
SHA256 e76c3884ab9935ac60c38370210747465b76fadda5acd3470e199f7c7070af06
offset ELF 0x4ecc
e2 03 01 2a    mov w2,w1
```

Patch :

```text
02 00 80 52    mov w2,#0
SHA256 3d89603ed3025bdc14e65d6269024c52920808c747aeb2d79417741d7cc7f9f6
```

Le correctif force le callback final d'énumération à annoncer `remaining_templates = 0`.

### Procédure recommandée

Téléphone dans **TWRP**, depuis la racine du dépôt :

```bash
./scripts/fix-microarray-fingerprint.sh
```

Le script :

- monte `/vendor` en RW ;
- vérifie le SHA256 du fichier présent ;
- s'arrête si le binaire est inconnu ;
- sauvegarde l'original dans `backups/fingerprint/` ;
- vérifie les 4 octets attendus avant de les modifier ;
- vérifie le hash final ;
- écrit dans le fichier existant avec `cat >` pour conserver l'inode/xattrs ;
- contrôle le contexte SELinux après écriture ;
- est idempotent si le hash patché est déjà présent.

**Ne force pas ce patch sur une autre version de `libfprint-x64.so`.** Il faut d'abord analyser ce binaire.

---

## English

### Symptom

On crDroid 7.16 / Android 11 on the S55:

- fingerprint enrollment works during first setup;
- after the first reboot, fingerprint authentication stops responding;
- adding another fingerprint also fails;
- the physical sensor still responds in navigation mode;
- the HAL process stays alive.

Android logs show new authentication/enrollment clients blocked by:

```text
Internal cleanup in progress
```

### Why PHH `nocleanup` is not enough

`persist.sys.phh.fingerprint.nocleanup=true` is a known GSI workaround and helps some devices. A clean early-boot test on this S55 **did not fix the issue**.

The Android 11 `services.jar` implementation uses that property in `InternalEnumerateClient.doTemplateCleanup()` to avoid deleting unknown software templates. It does **not bypass enumeration itself**. A legacy HAL that never reaches a terminal enumeration state can still block the framework forever.

### Exact root cause validated on this S55

`/vendor/lib64/hw/microarray.fingerprint.default.so` imports `bio_enumerate` from:

```text
/vendor/lib64/libfprint-x64.so
```

In the tested binary, `bio_enumerate()` calls `ma_tac_enumerate` and then `enumerate_notify`. The old implementation can send a non-terminal `remaining_templates` value when a template exists.

Android defines `remaining_templates` as the **number of additional enumeration messages expected**. The terminal state must therefore reach `0`. Android 11 keeps `InternalEnumerateClient` active until that happens.

This directly explains why the failure appears **after enrolling a fingerprint and rebooting**.

### Validated patch

```text
File: /vendor/lib64/libfprint-x64.so
Original SHA256: e76c3884ab9935ac60c38370210747465b76fadda5acd3470e199f7c7070af06
ELF offset: 0x4ecc
Original bytes: e2 03 01 2a    mov w2,w1
Patched bytes:  02 00 80 52    mov w2,#0
Patched SHA256: 3d89603ed3025bdc14e65d6269024c52920808c747aeb2d79417741d7cc7f9f6
```

Run from the repository root while the phone is in **TWRP**:

```bash
./scripts/fix-microarray-fingerprint.sh
```

The script is hash-guarded and refuses unknown vendor binaries.

## References

- Android fingerprint HAL contract: https://android.googlesource.com/platform/hardware/libhardware/+/f1ccec1/include/hardware/fingerprint.h
- Fingerprint 2.1 interface: https://android.googlesource.com/platform/hardware/interfaces/+/refs/heads/android16-release/biometrics/fingerprint/2.1/IBiometricsFingerprint.hal
- Oreo 2.1 callback bridge: https://android.googlesource.com/platform/hardware/interfaces/+/oreo-dr1-release/biometrics/fingerprint/2.1/default/BiometricsFingerprint.cpp
- PHH/Treble common fixes: https://github.com/TadiT7/treble_experimentations_wiki/blob/master/Common-Issues-and-fixes.md
