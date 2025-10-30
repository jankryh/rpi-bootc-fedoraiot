# Fedora IoT bootc Image Builder for Raspberry Pi 4

This project enables you to create a bootable Fedora IoT image for Raspberry Pi 4 using bootc technology and containers.

## Features

- **Automated build process** - Single command to create the entire image
- **Containerized approach** - Uses Podman for reproducible builds
- **SSH access** - Automatic SSH key injection for secure remote access
- **NetworkManager** - Full network configuration support
- **Optimized for RPi4** - Proper firmware, bootloader, and kernel

## Requirements

- **Fedora Linux** (recommended Fedora 40+) for full image building
- **macOS** (Apple Silicon M1–M4) for container building only
- Podman
- On Linux: root access (sudo) and basic tools `parted`, `rsync`, `losetup`, `mkfs.vfat`, `mkfs.ext4`

### Install on Fedora Linux:

```bash
sudo dnf install -y podman parted rsync dosfstools e2fsprogs
```

### Install on macOS:

```bash
brew install podman
podman machine init --cpus 8 --memory 8192 --disk-size 100
podman machine start
```

**Note for macOS users:** 
- Full build process works directly on macOS (Apple Silicon M1–M4) using Podman machine
- No Linux VM required - `build.sh` automatically runs Linux tools inside Podman machine's Linux VM
- Simply run `./build.sh` (without sudo) and it will handle everything

## Quick Start

### 1. Clone the project

```bash
git clone https://github.com/your-username/rpi-bootc-fedoraiot.git
cd rpi-bootc-fedoraiot
```

### 2. Build the image

On Fedora Linux:

```bash
sudo ./build.sh
```

On macOS (M1–M4):

```bash
./build.sh
```

Note: Do not use sudo on macOS. Podman Machine is per-user and must run as your normal user. You can also use `make image`.

The script automatically:
1. Detects your SSH key (`~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`)
2. Creates a bootc container with Fedora IoT for ARM64
3. Exports the filesystem from the container
4. Creates a 10GB bootable disk image with GPT partition table
5. Copies all files and installs the bootloader
6. Generates `fedora-iot-rpi4-bootc.img` ready to write

### 3. Write to SD card

Identify your SD card device name:

```bash
lsblk
```

Write the image to the SD card (replace device accordingly):

- Linux:

```bash
sudo dd if=fedora-iot-rpi4-bootc.img of=/dev/sdX bs=4M status=progress && sync
```

- macOS (find device with `diskutil list`, then use `rdiskN` for speed):

```bash
diskutil list
sudo diskutil unmountDisk /dev/diskN
sudo dd if=fedora-iot-rpi4-bootc.img of=/dev/rdiskN bs=4m && sync
```

⚠️ **WARNING:** Make sure you're writing to the correct device! This command will overwrite all data on the target disk.

### 4. Boot Raspberry Pi

1. Insert the SD card into Raspberry Pi 4
2. Connect power
3. RPi4 will boot from the SD card

## SSH Access

After boot, you can connect via SSH:

```bash
ssh fedora@<IP_ADDRESS>
```

or

```bash
ssh root@<IP_ADDRESS>
```

Your SSH key is automatically configured for both users.

## Project Structure

```
.
├── Containerfile          # bootc container image definition
├── build.sh              # Main build script
└── README.md             # This documentation
```

## How It Works

### 1. Containerfile

Defines the Fedora IoT bootc image:
- Base image: `quay.io/fedora/fedora-bootc:41`
- Installs RPi4 firmware and kernel
- Configures NetworkManager
- Adds SSH keys
- Sets up udev rules for boot

### 2. Build script

`build.sh` performs the following steps:

1. **SSH key detection** - Automatically finds your public SSH key
2. **Container build** - Creates ARM64 bootc container using `podman build --arch aarch64`
3. **Filesystem export** - Exports container contents
4. **Disk image creation**:
   - Creates 10GB file using `dd`
   - Creates GPT partition table with EFI and root partitions
   - Formats partitions (FAT32 for EFI, ext4 for root)
5. **Data copy** - Uses `rsync` to copy the filesystem
6. **Bootloader installation** - Copies RPi4 firmware and U-Boot
7. **Cleanup** - Unmounts and cleans up temporary files

## Advanced Configuration

### Custom SSH key

You can specify a custom SSH key as a parameter:

```bash
sudo ./build.sh "ssh-ed25519 AAAA..."
```

### Modify Containerfile

To add additional software, edit the `Containerfile`:

```dockerfile
RUN dnf install -y vim htop
```

### Change image size

Edit the line in `build.sh`:

```bash
dd if=/dev/zero of=${OUTPUT_IMAGE} bs=1M count=10240 status=progress
```

Change `count=10240` (10GB) to your desired size in MB.

## Troubleshooting

### Error: "Container does not exist"

The build creates the container automatically. For rebuild:

```bash
sudo podman rmi localhost/fedora-iot-rpi4:latest
sudo ./build.sh
```

### Error: "Permission denied" when writing to SD card

Make sure you're using the correct device and have root access:

```bash
sudo dd if=fedora-iot-rpi4-bootc.img of=/dev/sdX bs=4M status=progress && sync
```

### Error: "cannot run command \"podman machine start\" as root" on macOS

Cause: The script was run with `sudo` on macOS. Podman Machine is per-user and cannot be controlled as root.

Fix:

```bash
# On macOS, run without sudo
./build.sh
# or
make image
```

### RPi4 doesn't boot

1. Check that you have the correct model (RPi 4 or 400)
2. Ensure the SD card is properly formatted
3. Try rebuilding the image: `sudo ./build.sh`

### SSH key not accepted

Verify the key was properly injected:

```bash
# If image is not written yet (Linux or macOS):
podman run --rm localhost/fedora-iot-rpi4:latest cat /var/roothome/.ssh/authorized_keys
```

## Additional Resources

- [Fedora IoT Documentation](https://docs.fedoraproject.org/en-US/iot/)
- [bootc Project](https://github.com/containers/bootc)
- [Raspberry Pi 4 Documentation](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html)

## Notes

- Image is optimized for Raspberry Pi 4 (Model B and 400)
- Default image size is 10GB
- Uses U-Boot as bootloader
- Supports EFI boot
- NetworkManager is active for easy network configuration

## Contributing

Contributions are welcome! Create an issue or pull request.

## License

MIT License - free to use, modify, and distribute.

---

Created for Fedora IoT and Raspberry Pi community
