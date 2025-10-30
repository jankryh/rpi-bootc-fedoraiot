# 🧩 Fedora IoT bootc image for Raspberry Pi 4
FROM quay.io/fedora/fedora-bootc:42
# ==========================================================
ARG PUBKEY
ARG SELINUX_MODE=permissive


# If the above image is not accessible,
# uncomment the following line instead:
# FROM quay.io/fedora-bootc/fedora-bootc:latest

LABEL name="fedora-iot-bootc-rpi4" \
      summary="Fedora IoT bootc image for Raspberry Pi 4" \
      maintainer="Honza Kryhut <jkryhut@redhat.com>"

# ------------------------------------------------------
# 🧩 Basic firmware and kernel for Raspberry Pi 4
# ------------------------------------------------------
RUN microdnf install -y \
      bcm283x-firmware \
      bcm283x-overlays \
      uboot-images-armv8 \
      grub2-efi-aa64 \
      kernel-core \
      kernel-modules \
      kernel-modules-extra \
      dracut-network \
      NetworkManager \
      systemd-udev \
      e2fsprogs \
      util-linux \
      vim-minimal \
      podman \
      htop \
      tmux \
      iotop \
      && microdnf clean all

# ------------------------------------------------------
# ⚙️ Bootc runtime and ostree (fallback for non-IoT base)
# ------------------------------------------------------
RUN microdnf install -y bootc rpm-ostree ostree && microdnf clean all || true

# ------------------------------------------------------
# ⚙️ Configure hostname, network and SSH
# ------------------------------------------------------
RUN echo "rpi4-bootc" > /etc/hostname && \
    mkdir -p /etc/systemd/network && \
    printf '[Match]\nName=e*\n\n[Network]\nDHCP=yes\n' > /etc/systemd/network/20-wired.network && \
    mkdir -p /etc/systemd/system/multi-user.target.wants && \
    ln -sf /usr/lib/systemd/system/systemd-networkd.service /etc/systemd/system/multi-user.target.wants/systemd-networkd.service && \
    ln -sf /usr/lib/systemd/system/NetworkManager.service /etc/systemd/system/multi-user.target.wants/NetworkManager.service && \
    ln -sf /usr/lib/systemd/system/sshd.service /etc/systemd/system/multi-user.target.wants/sshd.service

# ------------------------------------------------------
# 🔐 SSH key for access (replace with your own)
# ------------------------------------------------------
# Insert SSH key into the correct location (bootc uses /var/roothome)
RUN mkdir -p /var/roothome && \
    if [ -n "${PUBKEY}" ]; then \
      mkdir -p /var/roothome/.ssh && \
      echo "${PUBKEY}" > /var/roothome/.ssh/authorized_keys && \
      chmod 700 /var/roothome/.ssh && chmod 600 /var/roothome/.ssh/authorized_keys; \
    fi && \
    ln -sfn /var/roothome /root


# ------------------------------------------------------
# 🧰 UEFI / Boot configuration for Raspberry Pi 4
# ------------------------------------------------------
RUN mkdir -p /boot/efi && \
    echo "enable_uart=1" >> /boot/config.txt && \
    echo "dtoverlay=vc4-kms-v3d" >> /boot/config.txt && \
    echo "gpu_mem=128" >> /boot/config.txt

# ------------------------------------------------------
# 🧠 Configure SELinux, journald, bootc storage
# ------------------------------------------------------
RUN systemctl enable systemd-journald && \
    mkdir -p /var/lib/bootc && \
    touch /etc/machine-id && \
    echo "SELINUX=${SELINUX_MODE}" > /etc/selinux/config

# ------------------------------------------------------
# 🚀 Clean system ready for bootc deploy
# ------------------------------------------------------
RUN rm -rf /var/cache/* /tmp/*

CMD ["/sbin/init"]
