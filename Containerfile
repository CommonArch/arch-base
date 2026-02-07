FROM docker.io/library/archlinux:base-devel AS pacstrap

ARG ARCH_ARCHIVE_DATE=2026/02/07
ARG ARCH_ARCHIVE_SERVER=https://archive.archlinux.org/repos

RUN pacman-key --init
RUN pacman -Sy --needed --noconfirm archlinux-keyring arch-install-scripts

WORKDIR /

COPY pacstrap-docker /usr/bin
RUN <<EOF cat > /etc/pacman.conf
[options]
Architecture = auto
ParallelDownloads = 6
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Never

[core]
Server = $ARCH_ARCHIVE_SERVER/$ARCH_ARCHIVE_DATE/core/os/\$arch

[extra]
Server = $ARCH_ARCHIVE_SERVER/$ARCH_ARCHIVE_DATE/extra/os/\$arch
EOF

RUN rm -rf /rootfs; mkdir /rootfs; pacstrap-docker /rootfs base

FROM scratch AS root

COPY --from=pacstrap /rootfs/ /

RUN install-packages-build base git grub nano squashfs-tools sudo xorriso networkmanager bluez; yes | pacman -Scc
RUN systemctl enable NetworkManager; systemctl enable bluetooth

RUN echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

ARG BRANCH=main
ARG VARIANT=general
ARG DESKTOP=nogui

ARG SYSTEM_CLI_VERSION=0.1.0
ARG SYSTEM_CLI_SHA256SUM=ec5d01cdd8a7591b444cfb24d0d0415c76da2b38091b0c1c02a619d33bce172e

RUN if [ "$VARIANT" != container ]; then install-packages-build linux-zen linux-firmware linux-zen-headers broadcom-wl-dkms dracut; fi; yes | pacman -Scc

RUN if [ "$DESKTOP" == gnome ]; then install-packages-build gnome; \
  elif [ "$DESKTOP" == plasma ]; then install-packages-build plasma kde-utilities-meta kde-accessibility-meta; \
  fi; yes | pacman -Scc

RUN if [ "$DESKTOP" == gnome ]; then install-packages-build xorg-server gdm; systemctl enable gdm; \
  elif [ "$DESKTOP" == plasma ]; then install-packages-build xorg-server sddm; systemctl enable sddm; \
  fi; yes | pacman -Scc

RUN if [ "$VARIANT" == nvidia ]; then install-packages-build nvidia-dkms; fi; yes | pacman -Scc

RUN install-packages-build grub efibootmgr; yes | pacman -Scc

RUN install-packages-build python-yaml python-click python-fasteners skopeo umoci jq libnotify wget; yes | pacman -Scc

COPY overlays/common /

RUN wget -O cli.tar.gz https://github.com/CommonArch/system-cli/archive/refs/tags/v"$SYSTEM_CLI_VERSION".tar.gz \
 && echo "$SYSTEM_CLI_SHA256SUM cli.tar.gz" | sha256sum --check --status \
 && tar xf cli.tar.gz && cp -ax system-cli-"$SYSTEM_CLI_VERSION"/usr/* /usr && rm -rf cli.tar.gz system-cli-"$SYSTEM_CLI_VERSION"

RUN systemctl enable commonarch-update-cleanup
RUN systemctl enable --global commonarch-update-check

# Clean up cache
RUN yes | pacman -Scc
