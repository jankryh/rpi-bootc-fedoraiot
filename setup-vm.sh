#!/bin/bash
# Setup UTM VM for Fedora ARM64 to build RPi4 image
# Requires UTM app installed from getutm.app
# Run: chmod +x setup-vm.sh && ./setup-vm.sh

set -euo pipefail

echo "🖥️  Setting up UTM VM for Fedora ARM64..."

# 1. Download Fedora ARM64 ISO (Cloud edition, ~2 GB)
ISO_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/42/Cloud/aarch64/images/Fedora-Cloud-Base-42-20241019.0.aarch64.raw.xz"
ISO_FILE="Fedora-Cloud-Base-42.aarch64.raw.xz"
if [ ! -f "$ISO_FILE" ]; then
  echo "📥 Downloading Fedora ARM64 ISO (~2 GB, may take 5-10 min)..."
  curl -L -o "$ISO_FILE" "$ISO_URL"
  unxz "$ISO_FILE"
  ISO_FILE="${ISO_FILE%.xz}"
fi

# 2. Create UTM config (.utm file)
VM_NAME="Fedora-ARM64-RPi-Build"
UTM_CONFIG="${VM_NAME}.utm"

cat > "$UTM_CONFIG" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>VMName</key>
  <string>${VM_NAME}</string>
  <key>VMArchitecture</key>
  <string>aarch64</string>
  <key>VMDisplay</key>
  <dict>
    <key>DisplayConsoleAgent</key>
    <true/>
    <key>DisplayResolution</key>
    <string>1024x768</string>
  </dict>
  <key>VMHardware</key>
  <dict>
    <key>CPUCount</key>
    <integer>4</integer>
    <key>MemorySize</key>
    <integer>8192</integer>
    <key>SystemDrives</key>
    <array>
      <dict>
        <key>DrivePath</key>
        <string>${ISO_FILE}</string>
        <key>DriveInterface</key>
        <string>virtio</string>
        <key>DriveReadOnly</key>
        <true/>
      </dict>
    </array>
  </dict>
  <key>VMNetwork</key>
  <dict>
    <key>InterfaceType</key>
    <string>emulated</string>
  </dict>
  <key>VMSharing</key>
  <dict>
    <key>SharedDirectory</key>
    <string>/Users/$(whoami)/Projects/rpi-bootc-fedoraiot</string>
    <key>SharedDirectoryReadOnly</key>
    <false/>
  </dict>
</dict>
</plist>
EOF

echo "✅ UTM config created: ${UTM_CONFIG}"
echo "📁 Shared folder: $(pwd) will be accessible in VM as /Volumes/shared"

# 3. Open UTM and import the config (manual step - UTM doesn't have CLI for this yet)
echo ""
echo "🚀 Next steps:"
echo "1. Open UTM app (if not installed, download from getutm.app)"
echo "2. Drag & drop ${UTM_CONFIG} into UTM to create VM"
echo "3. Start the VM (it will boot from ISO)"
echo "4. In VM terminal:"
echo "   sudo dnf install -y podman git parted rsync dosfstools e2fsprogs"
echo "   cd /Volumes/shared"
echo "   sudo ./build.sh  # This will create the .img"
echo "5. Copy the .img from shared folder back to macOS"
echo "6. Flash to SD card: diskutil list && sudo dd if=fedora-iot-rpi4-bootc.img of=/dev/rdiskN bs=4m && sync"

echo ""
echo "VM specs: 4 CPU, 8GB RAM, shared folder with project."
echo "Build time in VM: ~5-10 min on M4 Pro."
echo "After build, you can delete the VM."

# Optional: Open UTM if installed
if [ -d "/Applications/UTM.app" ]; then
  open "/Applications/UTM.app"
fi
