#!/usr/bin/env bash
# Fedora IoT bootc Image Builder for Raspberry Pi 4
# Usage: sudo ./build.sh [SSH_PUBLIC_KEY]

set -euo pipefail

OS=$(uname -s)
if [ "$OS" != "Darwin" ] && [ "$EUID" -ne 0 ]; then 
  echo "❌ This script must be run as root on Linux!"
  echo "Usage: sudo ./build.sh"
  exit 1
fi

# Detect SSH key (works on Linux and macOS)
if [ -n "${1:-}" ]; then
  PUBKEY="$1"
else
  PUBKEY=""
  CANDIDATE_USERS=()
  if [ -n "${SUDO_USER:-}" ]; then CANDIDATE_USERS+=("$SUDO_USER"); fi
  if [ -n "${USER:-}" ]; then CANDIDATE_USERS+=("$USER"); fi
  for U in "${CANDIDATE_USERS[@]}"; do
    USER_HOME=$(eval echo "~$U")
    if [ -f "${USER_HOME}/.ssh/id_ed25519.pub" ]; then
      PUBKEY=$(cat "${USER_HOME}/.ssh/id_ed25519.pub"); break
    elif [ -f "${USER_HOME}/.ssh/id_rsa.pub" ]; then
      PUBKEY=$(cat "${USER_HOME}/.ssh/id_rsa.pub"); break
    fi
  done
  if [ -z "$PUBKEY" ]; then
    echo "⚠️  SSH key not found, continuing without it..."
  fi
fi

IMAGE_NAME="fedora-iot-rpi4"
OUTPUT_IMAGE="${IMAGE_NAME}-bootc.img"
CONTAINER_TAG="localhost/${IMAGE_NAME}:latest"

echo "═══════════════════════════════════════════════════════════════"
echo "  Fedora IoT bootc Image Builder for Raspberry Pi 4"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ------------------------------------------------------------
# 🏗️  1. Build container image
# ------------------------------------------------------------
echo "🏗️  Building container image..."
podman build --arch aarch64 \
  ${PUBKEY:+--build-arg PUBKEY="$PUBKEY"} \
  -t ${CONTAINER_TAG} -f Containerfile

echo "✅ Container created: ${CONTAINER_TAG}"

# ------------------------------------------------------------
# 💾 2. Export root filesystem from container
# ------------------------------------------------------------
echo "📤 Exporting container filesystem..."
podman export $(podman create ${CONTAINER_TAG}) -o rootfs.tar
echo "✅ Filesystem exported to: $(pwd)/rootfs.tar"

# ------------------------------------------------------------
# 🧪 3. Create bootable disk image
# ------------------------------------------------------------
OS=$(uname -s)
if [ "$OS" = "Darwin" ]; then
  echo "🖥️  Detected macOS. Running Linux image creation inside a privileged Fedora container..."
  podman run --rm --privileged \
    -v "$(pwd)":/work -w /work \
    quay.io/fedora/fedora:41 bash -lc '
set -euo pipefail
dnf -y install parted e2fsprogs dosfstools util-linux rsync > /dev/null
TEMP_DIR=$(mktemp -d)
tar -xf rootfs.tar -C ${TEMP_DIR}
IMAGE_NAME="'"${IMAGE_NAME}"'"
OUTPUT_IMAGE="'"${OUTPUT_IMAGE}"'"
echo "💾 Creating disk image (10GB)..."
dd if=/dev/zero of=${OUTPUT_IMAGE} bs=1M count=10240 status=progress
echo "📊 Creating partition table..."
parted -s ${OUTPUT_IMAGE} mklabel gpt
parted -s ${OUTPUT_IMAGE} mkpart primary fat32 1MiB 513MiB
parted -s ${OUTPUT_IMAGE} set 1 esp on
parted -s ${OUTPUT_IMAGE} mkpart primary ext4 513MiB 100%
echo "🔗 Setting up loop device..."
LOOP_DEV=$(losetup -fP --show ${OUTPUT_IMAGE})
echo "Loop device: ${LOOP_DEV}"
echo "💿 Formatting partitions..."
mkfs.vfat -F32 ${LOOP_DEV}p1
mkfs.ext4 -F ${LOOP_DEV}p2
MOUNT_DIR=$(mktemp -d)
mount ${LOOP_DEV}p2 ${MOUNT_DIR}
mkdir -p ${MOUNT_DIR}/boot/efi
mount ${LOOP_DEV}p1 ${MOUNT_DIR}/boot/efi
echo "📋 Copying filesystem..."
rsync -aHA --no-xattrs ${TEMP_DIR}/ ${MOUNT_DIR}/ || true
echo "🥾 Installing bootloader..."
mkdir -p ${MOUNT_DIR}/boot/efi/EFI/BOOT
if [ -d ${MOUNT_DIR}/usr/share/uboot/rpi_arm64 ]; then
  cp ${MOUNT_DIR}/usr/share/uboot/rpi_arm64/u-boot.bin ${MOUNT_DIR}/boot/efi/
fi
if [ -d ${MOUNT_DIR}/usr/share/bcm283x-firmware ]; then
  cp -r ${MOUNT_DIR}/usr/share/bcm283x-firmware/* ${MOUNT_DIR}/boot/efi/
fi
cat > ${MOUNT_DIR}/boot/efi/config.txt << EOF
enable_uart=1
dtoverlay=vc4-kms-v3d
gpu_mem=128
arm_64bit=1
kernel=u-boot.bin
EOF
echo "🧹 Cleanup..."
sync
umount ${MOUNT_DIR}/boot/efi
umount ${MOUNT_DIR}
losetup -d ${LOOP_DEV}
rm -rf ${TEMP_DIR} ${MOUNT_DIR}
'
else
  # Linux host path (uses local tools)
  # Create empty disk image (10GB)
  echo "💾 Creating disk image (10GB)..."
  dd if=/dev/zero of=${OUTPUT_IMAGE} bs=1M count=10240 status=progress

  # Set up partition table
  echo "📊 Creating partition table..."
  parted -s ${OUTPUT_IMAGE} mklabel gpt
  parted -s ${OUTPUT_IMAGE} mkpart primary fat32 1MiB 513MiB
  parted -s ${OUTPUT_IMAGE} set 1 esp on
  parted -s ${OUTPUT_IMAGE} mkpart primary ext4 513MiB 100%

  # Mount using loopback
  echo "🔗 Mounting disk image..."
  LOOP_DEV=$(losetup -fP --show ${OUTPUT_IMAGE})
  echo "Loop device: ${LOOP_DEV}"

  # Format partitions
  echo "💿 Formatting partitions..."
  mkfs.vfat -F32 ${LOOP_DEV}p1
  mkfs.ext4 -F ${LOOP_DEV}p2

  # Mount filesystems
  MOUNT_DIR=$(mktemp -d)
  mount ${LOOP_DEV}p2 ${MOUNT_DIR}
  mkdir -p ${MOUNT_DIR}/boot/efi
  mount ${LOOP_DEV}p1 ${MOUNT_DIR}/boot/efi

  # Extract and copy filesystem from rootfs.tar
  TEMP_DIR=$(mktemp -d)
  tar -xf rootfs.tar -C ${TEMP_DIR}
  echo "📋 Copying filesystem from container to image..."
  rsync -aHA --no-xattrs ${TEMP_DIR}/ ${MOUNT_DIR}/ || {
      if [ $? -eq 23 ]; then
          echo "⚠️  Some xattr attributes were not copied (normal for FAT32)"
      else
          exit $?
      fi
  }

  # Install bootloader for Raspberry Pi
  echo "🥾 Installing bootloader..."
  mkdir -p ${MOUNT_DIR}/boot/efi/EFI/BOOT

  # Copy U-Boot and firmware for RPi4
  if [ -d ${MOUNT_DIR}/usr/share/uboot/rpi_arm64 ]; then
      cp ${MOUNT_DIR}/usr/share/uboot/rpi_arm64/u-boot.bin ${MOUNT_DIR}/boot/efi/
  fi

  # Copy RPi firmware
  if [ -d ${MOUNT_DIR}/usr/share/bcm283x-firmware ]; then
      cp -r ${MOUNT_DIR}/usr/share/bcm283x-firmware/* ${MOUNT_DIR}/boot/efi/
  fi

  # Create config.txt for RPi4
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
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ SUCCESS! Image created: ${OUTPUT_IMAGE}"
echo "═══════════════════════════════════════════════════════════════"
echo ""
ls -lh ${OUTPUT_IMAGE}
echo ""
echo "🔜 Write to SD card:"
echo "   sudo dd if=${OUTPUT_IMAGE} of=/dev/sdX bs=4M status=progress && sync"
echo ""
