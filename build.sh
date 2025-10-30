#!/usr/bin/env bash
# Fedora IoT bootc Image Builder for Raspberry Pi 4
# Supports: Linux (native) and macOS (via Podman machine)
# Usage: ./build.sh [SSH_PUBLIC_KEY]

set -euo pipefail

# Detect OS early and guard against sudo on macOS
OS=$(uname -s)
if [ "$OS" = "Darwin" ] && [ "${EUID:-$(id -u)}" -eq 0 ]; then
  echo "❌ On macOS, do not run with sudo."
  echo "   Re-run as your user: ./build.sh"
  exit 1
fi

# Global cleanup variables for Linux branch
CLEAN_MOUNT_DIR=""
CLEAN_LOOP_DEV=""
CLEAN_MAPPER_BASE=""
CLEAN_TEMP_DIR=""

cleanup() {
  set +e
  if [ -n "$CLEAN_MOUNT_DIR" ] && [ -d "$CLEAN_MOUNT_DIR" ]; then
    mountpoint -q "$CLEAN_MOUNT_DIR/boot/efi" && umount "$CLEAN_MOUNT_DIR/boot/efi" 2>/dev/null || true
    mountpoint -q "$CLEAN_MOUNT_DIR" && umount "$CLEAN_MOUNT_DIR" 2>/dev/null || true
    rmdir "$CLEAN_MOUNT_DIR" 2>/dev/null || true
  fi
  if [ -n "$CLEAN_MAPPER_BASE" ]; then
    kpartx -dv "/dev/mapper/${CLEAN_MAPPER_BASE}" 2>/dev/null || true
  fi
  if [ -n "$CLEAN_LOOP_DEV" ]; then
    losetup -d "$CLEAN_LOOP_DEV" 2>/dev/null || true
  fi
  if [ -n "$CLEAN_TEMP_DIR" ] && [ -d "$CLEAN_TEMP_DIR" ]; then
    rm -rf "$CLEAN_TEMP_DIR" 2>/dev/null || true
  fi
}

# Detect SSH key
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
      PUBKEY=$(cat "${USER_HOME}/.ssh/id_ed25519.pub")
      break
    elif [ -f "${USER_HOME}/.ssh/id_rsa.pub" ]; then
      PUBKEY=$(cat "${USER_HOME}/.ssh/id_rsa.pub")
      break
    fi
  done
  if [ -z "$PUBKEY" ]; then
    echo "⚠️  SSH key not found, continuing without it..."
  else
    echo "✅ Using SSH key: $(echo "$PUBKEY" | cut -c1-50)..."
  fi
fi

IMAGE_NAME="fedora-iot-rpi4"
OUTPUT_IMAGE="${IMAGE_NAME}-bootc.img"
CONTAINER_TAG="localhost/${IMAGE_NAME}:latest"

echo "═══════════════════════════════════════════════════════════════"
echo "  Fedora IoT bootc Image Builder for Raspberry Pi 4"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check OS and setup environment
if [ "$OS" = "Darwin" ]; then
  # macOS: Check Podman machine
  if ! podman machine list 2>/dev/null | grep -q "Currently running"; then
    echo "❌ Podman machine is not running. Starting it now..."
    podman machine start
    sleep 5
  fi
  
  MACHINE_NAME=$(podman machine list | grep "Currently running" | awk '{print $1}' | head -1)
  if [ -z "$MACHINE_NAME" ]; then
    echo "❌ Failed to detect Podman machine. Please ensure Podman machine is running."
    exit 1
  fi
  echo "✅ Using Podman machine: ${MACHINE_NAME}"
fi

# 1. Build container image
echo "🏗️  Building container image..."
podman build --arch aarch64 \
  ${PUBKEY:+--build-arg PUBKEY="$PUBKEY"} \
  -t ${CONTAINER_TAG} -f Containerfile

echo "✅ Container created: ${CONTAINER_TAG}"

# 2. Create bootable disk image
if [ "$OS" = "Darwin" ]; then
  echo ""
  echo "🖥️  macOS detected: Running full build inside Podman machine (Linux VM)..."
  echo "   This will take ~5-10 minutes. Please wait..."
  echo ""
  
  # Copy container to Podman machine
  echo "📦 Exporting container to Podman machine..."
  podman save ${CONTAINER_TAG} | podman machine ssh ${MACHINE_NAME} "podman load"
  
  # Create build script for Podman machine - runs everything in a privileged container
  cat > /tmp/build-in-vm.sh << 'BUILD_SCRIPT'
#!/bin/bash
set -euo pipefail

IMAGE_NAME="fedora-iot-rpi4"
OUTPUT_IMAGE="${IMAGE_NAME}-bootc.img"
CONTAINER_TAG="localhost/${IMAGE_NAME}:latest"
WORK_DIR="/var/tmp/rpi-build"

# Cleanup function for container build
cleanup_container() {
  set +e
  if [ -n "${MOUNT_DIR:-}" ] && [ -d "${MOUNT_DIR:-}" ]; then
    mountpoint -q "${MOUNT_DIR}/boot/efi" && umount "${MOUNT_DIR}/boot/efi" 2>/dev/null || true
    mountpoint -q "${MOUNT_DIR}" && umount "${MOUNT_DIR}" 2>/dev/null || true
    rmdir "${MOUNT_DIR}" 2>/dev/null || true
  fi
  if [ -n "${LOOP_DEV:-}" ]; then
    if [ -n "${LOOP_BASE:-}" ]; then
      kpartx -dv "/dev/mapper/${LOOP_BASE}" 2>/dev/null || true
    fi
    losetup -d "${LOOP_DEV}" 2>/dev/null || true
  fi
  if [ -n "${TEMP_DIR:-}" ] && [ -d "${TEMP_DIR:-}" ]; then
    rm -rf "${TEMP_DIR}" 2>/dev/null || true
  fi
}

# Cleanup old build
rm -rf ${WORK_DIR}
mkdir -p ${WORK_DIR}
cd ${WORK_DIR}

echo "📤 Exporting container filesystem..."
podman export $(podman create ${CONTAINER_TAG}) -o rootfs.tar

echo "🚀 Running disk image build in privileged container..."
podman run --rm --privileged \
  -v ${WORK_DIR}:/work:Z \
  -v /dev:/dev \
  -w /work \
  quay.io/fedora/fedora:41 bash -c '
set -euo pipefail

# Variables for cleanup
MOUNT_DIR=""
TEMP_DIR=""
LOOP_DEV=""
LOOP_BASE=""

cleanup() {
  set +e
  if [ -n "${MOUNT_DIR}" ] && [ -d "${MOUNT_DIR}" ]; then
    mountpoint -q "${MOUNT_DIR}/boot/efi" && umount "${MOUNT_DIR}/boot/efi" 2>/dev/null || true
    mountpoint -q "${MOUNT_DIR}" && umount "${MOUNT_DIR}" 2>/dev/null || true
    rmdir "${MOUNT_DIR}" 2>/dev/null || true
  fi
  if [ -n "${LOOP_DEV}" ]; then
    if [ -n "${LOOP_BASE}" ]; then
      kpartx -dv "/dev/mapper/${LOOP_BASE}" 2>/dev/null || true
    fi
    losetup -d "${LOOP_DEV}" 2>/dev/null || true
  fi
  if [ -n "${TEMP_DIR}" ] && [ -d "${TEMP_DIR}" ]; then
    rm -rf "${TEMP_DIR}" 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

# Install required tools
echo "📦 Installing tools..."
dnf install -y parted e2fsprogs dosfstools util-linux rsync kpartx > /dev/null 2>&1

# Ensure loop module is loaded
modprobe loop || true
sleep 1

OUTPUT_IMAGE="'${OUTPUT_IMAGE}'"

echo "💾 Creating disk image (10GB)..."
dd if=/dev/zero of=${OUTPUT_IMAGE} bs=1M count=10240 status=progress

echo "📊 Creating partition table..."
parted -s ${OUTPUT_IMAGE} mklabel gpt
parted -s ${OUTPUT_IMAGE} mkpart primary fat32 1MiB 513MiB
parted -s ${OUTPUT_IMAGE} set 1 esp on
parted -s ${OUTPUT_IMAGE} mkpart primary ext4 513MiB 100%

echo "🔗 Setting up loop device..."
if ! LOOP_DEV=$(losetup -fP --show ${OUTPUT_IMAGE}); then
  echo "⚠️  losetup failed; retrying..."
  modprobe loop || true
  sleep 2
  LOOP_DEV=$(losetup -fP --show ${OUTPUT_IMAGE})
fi
echo "Loop device: ${LOOP_DEV}"

# Wait for partition devices
sleep 2
partprobe ${LOOP_DEV} || true
sleep 1

# Determine partition device paths, fallback to kpartx if needed
if [ -b "${LOOP_DEV}p1" ] && [ -b "${LOOP_DEV}p2" ]; then
  LOOP_P1="${LOOP_DEV}p1"
  LOOP_P2="${LOOP_DEV}p2"
else
  echo "Using kpartx for partition mapping..."
  kpartx -av ${LOOP_DEV}
  LOOP_BASE=$(basename ${LOOP_DEV})
  LOOP_P1="/dev/mapper/${LOOP_BASE}p1"
  LOOP_P2="/dev/mapper/${LOOP_BASE}p2"
  sleep 1
fi

echo "💿 Formatting partitions..."
mkfs.vfat -F32 ${LOOP_P1}
mkfs.ext4 -F ${LOOP_P2}

MOUNT_DIR=$(mktemp -d)
mount ${LOOP_P2} ${MOUNT_DIR}
mkdir -p ${MOUNT_DIR}/boot/efi
mount ${LOOP_P1} ${MOUNT_DIR}/boot/efi

echo "📋 Copying filesystem..."
TEMP_DIR=$(mktemp -d)
tar -xf rootfs.tar -C ${TEMP_DIR}
rsync -aHAX --no-xattrs ${TEMP_DIR}/ ${MOUNT_DIR}/

echo "🥾 Installing bootloader..."
mkdir -p ${MOUNT_DIR}/boot/efi/EFI/BOOT

if [ -d ${MOUNT_DIR}/usr/share/uboot/rpi_arm64 ]; then
  cp ${MOUNT_DIR}/usr/share/uboot/rpi_arm64/u-boot.bin ${MOUNT_DIR}/boot/efi/
fi

if [ -d ${MOUNT_DIR}/usr/share/bcm283x-firmware ]; then
  cp -r ${MOUNT_DIR}/usr/share/bcm283x-firmware/* ${MOUNT_DIR}/boot/efi/
fi

cat > ${MOUNT_DIR}/boot/efi/config.txt << "CFGEOF"
enable_uart=1
dtoverlay=vc4-kms-v3d
gpu_mem=128
arm_64bit=1
kernel=u-boot.bin
CFGEOF

echo "🧹 Cleanup..."
sync
umount ${MOUNT_DIR}/boot/efi
umount ${MOUNT_DIR}
rmdir ${MOUNT_DIR}
rm -rf ${TEMP_DIR} rootfs.tar

# Explicit cleanup before exit
if [ -n "${LOOP_BASE:-}" ]; then
  kpartx -dv "/dev/mapper/${LOOP_BASE}" 2>/dev/null || true
fi
losetup -d ${LOOP_DEV} 2>/dev/null || true

trap - EXIT INT TERM

echo "✅ Disk image created: /work/${OUTPUT_IMAGE}"
'

echo "✅ Build completed successfully!"
BUILD_SCRIPT

  chmod +x /tmp/build-in-vm.sh
  
  # Copy script to Podman machine and execute
  cat /tmp/build-in-vm.sh | podman machine ssh ${MACHINE_NAME} "cat > /var/tmp/build-in-vm.sh && chmod +x /var/tmp/build-in-vm.sh"
  
  # Run build
  echo "🚀 Running build (this takes ~5-10 min)..."
  podman machine ssh ${MACHINE_NAME} "/var/tmp/build-in-vm.sh"
  
  # Download image
  echo "📥 Downloading image from Podman machine..."
  podman machine ssh ${MACHINE_NAME} "cat /var/tmp/rpi-build/${OUTPUT_IMAGE}" > ${OUTPUT_IMAGE}
  
  # Cleanup
  podman machine ssh ${MACHINE_NAME} "rm -rf /var/tmp/rpi-build /var/tmp/build-in-vm.sh" 2>/dev/null || true
  rm -f /tmp/build-in-vm.sh
  
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "  ✅ SUCCESS! Image created: ${OUTPUT_IMAGE}"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  ls -lh ${OUTPUT_IMAGE}
  echo ""
  echo "🔜 Write to SD card:"
  echo "   diskutil list"
  echo "   sudo diskutil unmountDisk /dev/diskN"
  echo "   sudo dd if=${OUTPUT_IMAGE} of=/dev/rdiskN bs=4m && sync"
  echo ""

else
  # Linux native build
  trap cleanup EXIT INT TERM

  echo "📤 Exporting container filesystem..."
  podman export $(podman create ${CONTAINER_TAG}) -o rootfs.tar
  
  echo "💾 Creating disk image (10GB)..."
  dd if=/dev/zero of=${OUTPUT_IMAGE} bs=1M count=10240 status=progress

  echo "📊 Creating partition table..."
  parted -s ${OUTPUT_IMAGE} mklabel gpt
  parted -s ${OUTPUT_IMAGE} mkpart primary fat32 1MiB 513MiB
  parted -s ${OUTPUT_IMAGE} set 1 esp on
  parted -s ${OUTPUT_IMAGE} mkpart primary ext4 513MiB 100%

  echo "🔗 Setting up loop device..."
  modprobe loop || true
  LOOP_DEV=$(losetup -fP --show ${OUTPUT_IMAGE})
  echo "Loop device: ${LOOP_DEV}"
  CLEAN_LOOP_DEV="$LOOP_DEV"

  # Ensure kernel sees partitions
  partprobe ${LOOP_DEV} || true
  sleep 1

  # Determine partition device paths, fallback to kpartx if needed
  if [ -b "${LOOP_DEV}p1" ] && [ -b "${LOOP_DEV}p2" ]; then
    P1="${LOOP_DEV}p1"
    P2="${LOOP_DEV}p2"
  else
    echo "Using kpartx for partition mapping..."
    kpartx -av ${LOOP_DEV}
    LOOP_BASE=$(basename ${LOOP_DEV})
    P1="/dev/mapper/${LOOP_BASE}p1"
    P2="/dev/mapper/${LOOP_BASE}p2"
    CLEAN_MAPPER_BASE="${LOOP_BASE}"
    sleep 1
  fi

  echo "💿 Formatting partitions..."
  mkfs.vfat -F32 ${P1}
  mkfs.ext4 -F ${P2}

  MOUNT_DIR=$(mktemp -d)
  CLEAN_MOUNT_DIR="$MOUNT_DIR"
  mount ${P2} ${MOUNT_DIR}
  mkdir -p ${MOUNT_DIR}/boot/efi
  mount ${P1} ${MOUNT_DIR}/boot/efi

  echo "📋 Copying filesystem..."
  TEMP_DIR=$(mktemp -d)
  CLEAN_TEMP_DIR="$TEMP_DIR"
  tar -xf rootfs.tar -C ${TEMP_DIR}
  rsync -aHAX --no-xattrs ${TEMP_DIR}/ ${MOUNT_DIR}/

  echo "🥾 Installing bootloader..."
  mkdir -p ${MOUNT_DIR}/boot/efi/EFI/BOOT

  if [ -d ${MOUNT_DIR}/usr/share/uboot/rpi_arm64 ]; then
    cp ${MOUNT_DIR}/usr/share/uboot/rpi_arm64/u-boot.bin ${MOUNT_DIR}/boot/efi/
  fi

  if [ -d ${MOUNT_DIR}/usr/share/bcm283x-firmware ]; then
    cp -r ${MOUNT_DIR}/usr/share/bcm283x-firmware/* ${MOUNT_DIR}/boot/efi/
  fi

  cat > ${MOUNT_DIR}/boot/efi/config.txt << 'EOF'
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
  rm -rf ${TEMP_DIR} rootfs.tar

  # Explicit cleanup before removing trap
  if [ -n "$CLEAN_MAPPER_BASE" ]; then
    kpartx -dv "/dev/mapper/${CLEAN_MAPPER_BASE}" 2>/dev/null || true
  fi
  losetup -d ${LOOP_DEV} 2>/dev/null || true

  # Clear cleanup variables and remove trap
  CLEAN_MOUNT_DIR=""
  CLEAN_LOOP_DEV=""
  CLEAN_MAPPER_BASE=""
  CLEAN_TEMP_DIR=""
  trap - EXIT INT TERM

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
fi
