FROM quay.io/fedora-bootc/fedora-bootc:latest
# 🧩 Fedora IoT bootc image for Raspberry Pi 4
# S automatickým fallbackem na veřejný Fedora bootc base
# ==========================================================
ARG PUBKEY

# Primární pokus: Fedora IoT bootc (pokud Quay.io dovolí)
# Pokud selže, použij příkaz níže s veřejnou Fedora bootc image:
#   sed -i '1s/.*/FROM quay.io\/fedora-bootc\/fedora-bootc:latest/' Containerfile

#FROM quay.io/fedora-bootc/fedora-iot:latest
FROM quay.io/fedora/fedora-bootc:42


# Pokud výše uvedený image není přístupný,
# odkomentuj následující řádek místo něj:
# FROM quay.io/fedora-bootc/fedora-bootc:latest

LABEL name="fedora-iot-bootc-rpi4" \
      summary="Fedora IoT bootc image for Raspberry Pi 4" \
      maintainer="Honza Kryhut <jkryhut@redhat.com>"

# ------------------------------------------------------
# 🧩 Základní firmware a kernel pro Raspberry Pi 4
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
# ⚙️ Bootc runtime a ostree (fallback pro ne-IoT base)
# ------------------------------------------------------
RUN microdnf install -y bootc rpm-ostree ostree && microdnf clean all || true

# ------------------------------------------------------
# ⚙️ Nastavení hostname, networku a SSH
# ------------------------------------------------------
# ⚙️ Nastavení hostname, networku a SSH (bez systemctl enable)
RUN echo "rpi4-bootc" > /etc/hostname && \
    mkdir -p /etc/systemd/network && \
    printf '[Match]\nName=e*\n\n[Network]\nDHCP=yes\n' > /etc/systemd/network/20-wired.network && \
    mkdir -p /etc/systemd/system/multi-user.target.wants && \
    ln -sf /usr/lib/systemd/system/systemd-networkd.service /etc/systemd/system/multi-user.target.wants/systemd-networkd.service && \
    ln -sf /usr/lib/systemd/system/NetworkManager.service /etc/systemd/system/multi-user.target.wants/NetworkManager.service && \
    ln -sf /usr/lib/systemd/system/sshd.service /etc/systemd/system/multi-user.target.wants/sshd.service

# ------------------------------------------------------
# 🔐 SSH klíč pro přístup (nahraď svým)
# ------------------------------------------------------
# 🔐 SSH klíč pro přístup (nahraď svým)

# 🔐 Vložení SSH klíče do správného umístění (bootc používá /var/roothome)
RUN mkdir -p /var/roothome/.ssh && \
    echo "${PUBKEY}" > /var/roothome/.ssh/authorized_keys && \
    chmod 700 /var/roothome/.ssh && chmod 600 /var/roothome/.ssh/authorized_keys && \
    ln -sfn /var/roothome /root


# ------------------------------------------------------
# 🧰 UEFI / Boot konfigurace pro Raspberry Pi 4
# ------------------------------------------------------
RUN mkdir -p /boot/efi && \
    echo "enable_uart=1" >> /boot/config.txt && \
    echo "dtoverlay=vc4-kms-v3d" >> /boot/config.txt && \
    echo "gpu_mem=128" >> /boot/config.txt

# ------------------------------------------------------
# 🧠 Nastavení SELinux, journald, bootc storage
# ------------------------------------------------------
RUN systemctl enable systemd-journald && \
    mkdir -p /var/lib/bootc && \
    touch /etc/machine-id && \
    echo "SELINUX=permissive" > /etc/selinux/config

# ------------------------------------------------------
# 🚀 Čistý systém připravený pro bootc deploy
# ------------------------------------------------------
RUN rm -rf /var/cache/* /tmp/*

CMD ["/sbin/init"]
