# Fedora IoT bootc Image Builder for Raspberry Pi 4

Tento projekt umožňuje vytvořit bootable Fedora IoT image pro Raspberry Pi 4 pomocí bootc technologie a containerů.

## ✨ Vlastnosti

- 🔧 **Automatizovaný build proces** - Jeden příkaz pro vytvoření celého image
- 🐳 **Containerizovaný přístup** - Využití Podman pro reprodukovatelné buildy
- 🔐 **SSH přístup** - Automatické vložení SSH klíče pro bezpečný vzdálený přístup
- 🌐 **NetworkManager** - Plná podpora síťových konfigurací
- 🎯 **Optimalizováno pro RPi4** - Správné firmware, bootloader a kernel

## 📋 Požadavky

- Fedora Linux (doporučeno Fedora 40+)
- Podman
- Root přístup (sudo)
- Základní nástroje: `parted`, `rsync`, `losetup`, `mkfs.vfat`, `mkfs.ext4`

Instalace požadavků:

```bash
sudo dnf install -y podman parted rsync dosfstools e2fsprogs
```

## 🚀 Rychlý start

### 1. Stažení projektu

```bash
git clone https://github.com/your-username/rpi-bootc-fedoraiot.git
cd rpi-bootc-fedoraiot
```

### 2. Build image

```bash
sudo ./build.sh
```

Skript automaticky:
1. Detekuje váš SSH klíč (`~/.ssh/id_ed25519.pub` nebo `~/.ssh/id_rsa.pub`)
2. Vytvoří bootc container s Fedora IoT pro ARM64
3. Exportuje filesystem z containeru
4. Vytvoří 10GB bootable disk image s GPT partition table
5. Zkopíruje všechny soubory a nainstaluje bootloader
6. Vygeneruje `fedora-iot-rpi4-bootc.img` připravený k zápisu

### 3. Zápis na SD kartu

Zjistěte název zařízení SD karty:

```bash
lsblk
```

Zapište image na SD kartu (nahraďte `/dev/sdX` skutečným zařízením):

```bash
sudo dd if=fedora-iot-rpi4-bootc.img of=/dev/sdX bs=4M status=progress && sync
```

⚠️ **POZOR:** Ujistěte se, že píšete na správné zařízení! Tímto příkazem přepíšete veškerá data na cílovém disku.

### 4. Boot Raspberry Pi

1. Vložte SD kartu do Raspberry Pi 4
2. Připojte napájení
3. RPi4 bootne z SD karty

## 🔐 SSH Přístup

Po spuštění se můžete připojit pomocí SSH:

```bash
ssh fedora@<IP_ADDRESS>
```

nebo

```bash
ssh root@<IP_ADDRESS>
```

Váš SSH klíč je automaticky nakonfigurován pro oba uživatele.

## 📁 Struktura projektu

```
.
├── Containerfile          # Definice bootc container image
├── build.sh              # Hlavní build skript
└── README.md             # Tato dokumentace
```

## 🔧 Jak to funguje

### 1. Containerfile

Definuje Fedora IoT bootc image:
- Base image: `quay.io/fedora/fedora-bootc:41`
- Instaluje RPi4 firmware a kernel
- Konfiguruje NetworkManager
- Přidává SSH klíče
- Nastavuje udev pravidla pro boot

### 2. Build skript

`build.sh` provádí následující kroky:

1. **Detekce SSH klíče** - Automaticky nalezne váš veřejný SSH klíč
2. **Container build** - Vytvoří ARM64 bootc container pomocí `podman build --arch aarch64`
3. **Export filesystem** - Exportuje obsah containeru
4. **Vytvoření disk image**:
   - Vytvoří 10GB soubor pomocí `dd`
   - Vytvoří GPT partition table s EFI a root partitions
   - Naformátuje partitions (FAT32 pro EFI, ext4 pro root)
5. **Kopírování dat** - Použije `rsync` pro zkopírování filesystemu
6. **Instalace bootloaderu** - Zkopíruje RPi4 firmware a U-Boot
7. **Cleanup** - Odmountuje a uklidí dočasné soubory

## ⚙️ Pokročilá konfigurace

### Vlastní SSH klíč

Můžete zadat vlastní SSH klíč jako parametr:

```bash
sudo ./build.sh "ssh-ed25519 AAAA..."
```

### Modifikace Containerfile

Pro přidání dalšího software upravte `Containerfile`:

```dockerfile
RUN dnf install -y vim htop
```

### Změna velikosti image

Upravte v `build.sh` řádek:

```bash
dd if=/dev/zero of=${OUTPUT_IMAGE} bs=1M count=10240 status=progress
```

Změňte `count=10240` (10GB) na požadovanou velikost v MB.

## 🐛 Troubleshooting

### Chyba: "Container neexistuje"

Build nejprve vytvoří container automaticky. Pokud chcete rebuild:

```bash
sudo podman rmi localhost/fedora-iot-rpi4:latest
sudo ./build.sh
```

### Chyba: "Permission denied" při zápisu na SD kartu

Ujistěte se, že používáte správné zařízení a máte root přístup:

```bash
sudo dd if=fedora-iot-rpi4-bootc.img of=/dev/sdX bs=4M status=progress && sync
```

### RPi4 nebootu

1. Zkontrolujte, že máte správný model (RPi 4 nebo 400)
2. Ujistěte se, že SD karta je správně zformátována
3. Zkuste rebuild image: `sudo ./build.sh`

### SSH klíč není přijímán

Ověřte, že klíč byl správně vložen:

```bash
# Pokud image ještě není zapsán:
sudo podman run --rm localhost/fedora-iot-rpi4:latest cat /root/.ssh/authorized_keys
```

## 📚 Další zdroje

- [Fedora IoT Documentation](https://docs.fedoraproject.org/en-US/iot/)
- [bootc Project](https://github.com/containers/bootc)
- [Raspberry Pi 4 Documentation](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html)

## 📝 Poznámky

- Image je optimalizován pro Raspberry Pi 4 (Model B i 400)
- Výchozí velikost image je 10GB
- Používá se U-Boot jako bootloader
- Podporuje EFI boot
- NetworkManager je aktivní pro snadnou konfiguraci sítě

## 🤝 Přispívání

Příspěvky jsou vítány! Vytvořte issue nebo pull request.

## 📄 Licence

MIT License - můžete volně používat, modifikovat a distribuovat.

---

Vytvořeno s ❤️ pro Fedora IoT a Raspberry Pi komunitu
