# ---------------------------------------------
# Enshrouded Proton image (GE-Proton, Debian trixie)
# Based on steamcmd/proton (Ptero-Eggs/yolks)
# ---------------------------------------------
FROM        debian:trixie-slim

LABEL       author="Torsten Widmann" maintainer="info@goover.de"
LABEL       org.opencontainers.image.source="https://github.com/dvkei/enshrouded-proton"

ARG         PROTON_VERSION=GE-Proton11-9

## install required packages
RUN         dpkg --add-architecture i386
RUN         apt update
RUN         apt install -y --no-install-recommends wget ca-certificates iproute2 gnupg2 libntlm0 winbind xvfb xauth libncurses-dev:i386 libncurses6 dbus libgdiplus lib32gcc-s1
RUN         apt install -y alsa-tools libpulse0 pulseaudio libpulse-dev libasound2t64 libao-common gnutls-bin gnupg locales numactl cabextract curl python3 python3-pip python3-setuptools tini file pipx libvulkan1 libfreetype6 libfreetype6:i386
RUN         useradd -d /home/container -m container

# Download Proton GE (pinned version, checksum verified)
RUN         cd /tmp \
            && curl -sSLO "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_VERSION}/${PROTON_VERSION}-x86_64.tar.gz" \
            && curl -sSLO "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_VERSION}/${PROTON_VERSION}-x86_64.sha512sum" \
            && sha512sum -c "${PROTON_VERSION}-x86_64.sha512sum" \
            && tar -xzf "${PROTON_VERSION}-x86_64.tar.gz" -C /usr/local/bin/ --strip-components=1 \
            && rm -f "${PROTON_VERSION}"-x86_64.*

# Proton Fix machine-id
RUN         rm -f /etc/machine-id
RUN         dbus-uuidgen --ensure=/etc/machine-id
RUN         rm -f /var/lib/dbus/machine-id
RUN         dbus-uuidgen --ensure

#Setup Protontricks
RUN         PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install protontricks

# Set up Winetricks
RUN	        wget -q -O /usr/sbin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
            && chmod +x /usr/sbin/winetricks

## install rcon
RUN         cd /tmp/ \
            && curl -sSL https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz > rcon.tar.gz \
            && tar xvf rcon.tar.gz \
            && mv rcon-0.10.3-amd64_linux/rcon /usr/local/bin/

USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

STOPSIGNAL SIGINT

COPY        --chown=container:container ./entrypoint.sh /entrypoint.sh
RUN         chmod +x /entrypoint.sh
ENTRYPOINT  ["/usr/bin/tini", "-g", "--"]
CMD         ["/entrypoint.sh"]
