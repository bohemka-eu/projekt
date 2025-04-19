# ----------------------------------
# Pterodactyl OBS Control Panel Dockerfile
# Environment: Node.js + OBS + noVNC
# Minimum Panel Version: 1.0.0
# Uses specific commit from public repository
# ----------------------------------
FROM alpine:3.18

LABEL maintainer="Bohemka <sprava_serveru@bohemka.eu>"

# Vytvoøení uživatele container pøed inicializací adresáøù
RUN adduser --disabled-password --home /home/container container \
    && echo "container ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/container

# Instalace základních závislostí
RUN apk add --no-cache --update \
    nodejs \
    npm \
    bash \
    curl \
    git \
    tar \
    sqlite \
    fontconfig \
    sudo \
    shadow \
    pulseaudio \
    mesa-dri-gallium \
    mesa-egl \
    dbus \
    && npm install -g npm@10.8.3 \
    && apk add --no-cache --virtual .build-deps \
    build-base \
    python3 \
    && apk add --no-cache \
    obs-studio \
    && apk add --no-cache \
    x11vnc \
    xvfb \
    && rm -rf /var/cache/apk/* \
    && mkdir -p /run/user/1000/pulse \
    && chown container:container /run/user/1000 /run/user/1000/pulse \
    && chmod 700 /run/user/1000 /run/user/1000/pulse \
    && mkdir -p /var/lib/dbus \
    && dbus-uuidgen > /var/lib/dbus/machine-id

# Instalace websockify pro noVNC
RUN apk add --no-cache python3 py3-pip \
    && pip3 install --no-cache-dir numpy websockify \
    && apk del py3-pip

# Instalace noVNC
RUN mkdir -p /usr/share/novnc \
    && curl -L https://github.com/novnc/noVNC/archive/refs/tags/v1.5.0.tar.gz | tar -xz -C /usr/share/novnc --strip-components=1 \
    && ln -s /usr/share/novnc/vnc.html /usr/share/novnc/index.html

# Nastavení /tmp/.X11-unix
RUN mkdir -p /tmp/.X11-unix \
    && chown root:root /tmp/.X11-unix \
    && chmod 1777 /tmp/.X11-unix

# Nastavení pracovního adresáøe
USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

# Stažení kódu z veøejného repozitáøe
ARG REPO_URL=https://github.com/bohemka-eu/projekt.git
ARG COMMIT_SHA=ee16daf
RUN git clone ${REPO_URL} /tmp/repo && \
    cd /tmp/repo && \
    git checkout ${COMMIT_SHA} && \
    echo "Debug: Content of /tmp/repo before move" && \
    ls -laR /tmp/repo && \
    mv /tmp/repo/* /tmp/repo/.[!.]* /home/container/ 2>/dev/null || true && \
    echo "Debug: Content of /home/container after move" && \
    ls -la /home/container && \
    rm -rf /tmp/repo

# Oprava cesty noVNC v server.js
RUN sed -i 's|/opt/noVNC|/usr/share/novnc|g' /home/container/server.js

# Inicializace adresáøù a souborù
RUN mkdir -p /home/container/data /home/container/.config/obs-studio/logs \
    && if [ ! -f "/home/container/data/uzivatele.json" ]; then \
        echo '{"admin":{"passwordHash":"$2b$10$BohemkajedeHashed"},"streamer":{"passwordHash":null}}' > /home/container/data/uzivatele.json; \
    fi \
    && if [ ! -f "/home/container/config.json" ]; then \
        echo '{"chat":{"username":"bohemka_bot"}}' > /home/container/config.json; \
    fi \
    && chmod 644 /home/container/data/uzivatele.json /home/container/config.json \
    && chmod -R 700 /home/container/.config

# Instalace Node.js závislostí
RUN npm install --production

# Oprávnìní pro skripty
RUN chmod +x /home/container/start.sh /home/container/entrypoint.sh /home/container/install.sh /home/container/server.js 2>/dev/null || true

# Nastavení portù
EXPOSE 3000 4455 6080 5900

# Vstupní bod
CMD ["/bin/bash", "/home/container/entrypoint.sh"]