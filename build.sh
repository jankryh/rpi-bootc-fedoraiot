#!/usr/bin/env bash
# Fedora IoT bootc Image Builder for Raspberry Pi 4
# Použití: sudo ./build.sh [SSH_PUBLIC_KEY]

set -euo pipefail

if [ "$EUID" -ne 0 ]; then 
  echo "❌ Tento skript musí běžet jako root!"
  echo "Použij: sudo ./build.sh"
  exit 1
fi

# Detekuj SSH klíč
if [ -n "${1:-}" ]; then
    PUBKEY="$1"
elif [ -n "${SUDO_USER:-}" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [ -f "${USER_HOME}/.ssh/id_ed25519.pub" ]; then
        PUBKEY=$(cat "${USER_HOME}/.ssh/id_ed25519.pub")
    elif [ -f "${USER_HOME}/.ssh/id_rsa.pub" ]; then
        PUBKEY=$(cat "${USER_HOME}/.ssh/id_rsa.pub")
    else
        echo "⚠️  SSH klíč nenalezen, pokračuji bez něj..."
        PUBKEY=""
    fi
else
    echo "⚠️  Nelze detekovat uživatele, pokračuji bez SSH klíče..."
    PUBKEY=""
fi

IMAGE_NAME="fedora-iot-rpi4"
OUTPUT_IMAGE="${IMAGE_NAME}-bootc.img"
CONTAINER_TAG="localhost/${IMAGE_NAME}:latest"

echo "═══════════════════════════════════════════════════════════════"
echo "  Fedora IoT bootc Image Builder pro Raspberry Pi 4"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ------------------------------------------------------------
# 🏗️  1. Build container image
# ------------------------------------------------------------
echo "🏗️  Building container image..."
podman build --arch aarch64 \
  ${PUBKEY:+--build-arg PUBKEY="$PUBKEY"} \
  -t ${CONTAINER_TAG} -f Containerfile

echo "✅ Container vytvořen: ${CONTAINER_TAG}"

# ------------------------------------------------------------
# 💾 2. Export a vytvoření bootable disk image
# ------------------------------------------------------------
# Export container filesystem
echo "📤 Exportuji container filesystem..."
TEMP_DIR=$(mktemp -d)
podman export $(podman create ${CONTAINER_TAG}) | tar -xf - -C ${TEMP_DIR}

echo "✅ Filesystem exportován do: ${TEMP_DIR}"

# Vytvoř prázdný disk image (10GB)
echo "💾 Vytvářím disk image (10GB)..."
dd if=/dev/zero of=${OUTPUT_IMAGE} bs=1M count=10240 status=progress

# Nastav partition table
echo "📊 Vytvářím partition table..."
parted -s ${OUTPUT_IMAGE} mklabel gpt
parted -s ${OUTPUT_IMAGE} mkpart primary fat32 1MiB 513MiB
parted -s ${OUTPUT_IMAGE} set 1 esp on
parted -s ${OUTPUT_IMAGE} mkpart primary ext4 513MiB 100%

# Mount pomocí loopback
echo "🔗 Mountuji disk image..."
LOOP_DEV=$(losetup -fP --show ${OUTPUT_IMAGE})
echo "Loop device: ${LOOP_DEV}"

# Formátuj partitions
echo "💿 Formátuji partitions..."
mkfs.vfat -F32 ${LOOP_DEV}p1
mkfs.ext4 -F ${LOOP_DEV}p2

# Mount filesystems
MOUNT_DIR=$(mktemp -d)
mount ${LOOP_DEV}p2 ${MOUNT_DIR}
mkdir -p ${MOUNT_DIR}/boot/efi
mount ${LOOP_DEV}p1 ${MOUNT_DIR}/boot/efi

# Zkopíruj filesystem z containeru
echo "📋 Kopíruji filesystem z containeru do image..."
rsync -aHA --no-xattrs ${TEMP_DIR}/ ${MOUNT_DIR}/ || {
    # Rsync exit code 23 = partial transfer due to xattr errors (OK for FAT32)
    if [ $? -eq 23 ]; then
        echo "⚠️  Některé xattr atributy nebyly zkopírovány (normální pro FAT32)"
    else
        exit $?
    fi
}

# Instaluj bootloader pro Raspberry Pi
echo "🥾 Instaluji bootloader..."
mkdir -p ${MOUNT_DIR}/boot/efi/EFI/BOOT

# Zkopíruj U-Boot a firmware pro RPi4
if [ -d ${MOUNT_DIR}/usr/share/uboot/rpi_arm64 ]; then
    cp ${MOUNT_DIR}/usr/share/uboot/rpi_arm64/u-boot.bin ${MOUNT_DIR}/boot/efi/
fi

# Zkopíruj RPi firmware
if [ -d ${MOUNT_DIR}/usr/share/bcm283x-firmware ]; then
    cp -r ${MOUNT_DIR}/usr/share/bcm283x-firmware/* ${MOUNT_DIR}/boot/efi/
fi

# Vytvoř config.txt pro RPi4
cat > ${MOUNT_DIR}/boot/efi/config.txt << 'EOF'
enable_uart=1
dtoverlay=vc4-kms-v3d
gpu_mem=128
arm_64bit=1
kernel=u-boot.bin
EOF

# Cleanup
echo "🧹 Cleanup..."
sync
umount ${MOUNT_DIR}/boot/efi
umount ${MOUNT_DIR}
losetup -d ${LOOP_DEV}
rm -rf ${TEMP_DIR} ${MOUNT_DIR}

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ SUCCESS! Image vytvořen: ${OUTPUT_IMAGE}"
echo "═══════════════════════════════════════════════════════════════"
echo ""
ls -lh ${OUTPUT_IMAGE}
echo ""
echo "🔜 Zapiš na SD card:"
echo "   sudo dd if=${OUTPUT_IMAGE} of=/dev/sdX bs=4M status=progress && sync"
echo ""

