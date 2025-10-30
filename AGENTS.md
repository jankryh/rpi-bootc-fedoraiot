# Repository Guidelines

## Project Structure & Module Organization
- `Containerfile` — Defines the Fedora IoT bootc image for Raspberry Pi 4 (aarch64).
- `build.sh` — One-shot builder: builds the container, exports rootfs, creates the bootable `.img`.
- `setup-vm.sh` — Optional helper to prepare a macOS UTM VM for Linux-only steps.
- `README.md` — Usage and troubleshooting.
- Generated artifacts (e.g., `fedora-iot-rpi4-bootc.img`, `rootfs.tar`) are ignored by `.gitignore`; do not commit them. Prefer placing outputs in `output/`.

## Build, Test, and Development Commands
- Build container + disk image (Fedora Linux): `sudo ./build.sh`
- Build via Podman machine (macOS M1–M4): `./build.sh`
- Rebuild from scratch: `podman rmi localhost/fedora-iot-rpi4:latest && ./build.sh`
- Lint shell scripts: `shellcheck build.sh setup-vm.sh`
- Format shell scripts: `shfmt -w build.sh setup-vm.sh`
- Validate Containerfile: `podman build --arch aarch64 -t localhost/fedora-iot-rpi4:dev -f Containerfile`

## Coding Style & Naming Conventions
- Shell (bash):
  - Use `set -euo pipefail` and quote expansions.
  - Two-space indentation; one command per line; descriptive vars.
  - Uppercase for constants (e.g., `IMAGE_NAME`), lowercase for locals when helpful.
- Containerfile:
  - Group related `RUN` steps; clean caches; avoid secrets. Prefer `microdnf` where possible.
  - Keep labels concise; use `ARG PUBKEY` for key injection.

## Testing Guidelines
- No unit test suite. Validate by:
  - Building the container: `podman build --arch aarch64 ...` and `podman run --rm <image> echo ok`.
  - Running `./build.sh` on Linux and confirming `fedora-iot-rpi4-bootc.img` exists.
  - Mounting the image to verify `/boot/efi/` contents and `config.txt`.
  - Optional hardware test: boot on RPi4 and `ssh fedora@<ip>` using your key.

## Commit & Pull Request Guidelines
- Use clear, imperative commits. Conventional style encouraged:
  - `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`
- PRs should include:
  - Purpose, platform used (Linux/macOS), key logs or output, and any risks.
  - For behavior changes, add before/after notes or example commands.

## Security & Configuration Tips
- Never commit private keys, credentials, or `.img`/`.tar` artifacts.
- Provide SSH access via `ARG PUBKEY` only; avoid hardcoding secrets.
- Large downloads/builds happen inside containers/VMs; verify commands before running with `sudo`.

## Agent-Specific Instructions
- Changes must follow this guide. Do not reformat unrelated files. Keep scope minimal and scripts idempotent.
