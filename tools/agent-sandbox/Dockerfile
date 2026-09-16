# Image for isolated agent GUI sandboxes: a virtual X display (Xvfb), a small
# window manager, a browser, and ffmpeg for recording — all driven inside the
# container, never on the host's desktop.
#
# Debian is used instead of Ubuntu so firefox-esr is a real deb package rather
# than a snap, which does not work inside a container.
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        xvfb \
        xauth \
        x11vnc \
        openbox \
        xterm \
        x11-apps \
        xdotool \
        imagemagick \
        ffmpeg \
        firefox-esr \
        pcmanfm \
        procps \
        fonts-dejavu-core \
        mesa-utils \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -u 1000 -s /bin/bash agent \
    && mkdir -p /output /logs /workspace \
    && chown agent:agent /output /logs /workspace

# Session bootstrap: virtual display, window manager, then wait.
COPY session.sh /usr/local/bin/session.sh
RUN chmod +x /usr/local/bin/session.sh

USER agent
WORKDIR /workspace

# The session script keeps the container alive; exec into it with
# `sandbox exec <name> <cmd>` and DISPLAY/XAUTHORITY come preconfigured.
CMD ["/usr/local/bin/session.sh"]
