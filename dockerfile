# ----------------------------------
# Pterodactyl OBS Control Panel Dockerfile
# Environment: Node.js + OBS + noVNC
# Minimum Panel Version: 1.0.0
# Uses specific commit from private repository
# ----------------------------------
FROM alpine:3.18

LABEL maintainer="Bohemka.eu <sprava_serveru@bohemka.eu>"

# Enable BuildKit (needed for secrets)
# syntax=docker/dockerfile:1.4

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
    && npm install -g npm@10.8.3 \
    && apk add --no-cache --virtual .build-deps \
    build-base \
    python3 \
    && apk add --no-cache \
    obs-studio \
    && apk add --no-cache \
    x11vnc \
    xvfb \
    && rm -rf /var/cache/apk/*

# Instalace websockify pro noVNC
RUN apk add --no-cache python3 py3-pip \
    && pip3 install --no-cache-dir numpy websockify \
    && apk del py3-pip

# Instalace noVNC (statické soubory z GitHubu)
RUN mkdir -p /usr/share/novnc \
    && curl -L https://github.com/novnc/noVNC/archive/refs/tags/v1.5.0.tar.gz | tar -xz -C /usr/share/novnc --strip-components=1 \
    && ln -s /usr/share/novnc/vnc.html /usr/share/novnc/index.html

# Nastavení /tmp/.X11-unix jako root
RUN mkdir -p /tmp/.X11-unix \
    && chown root:root /tmp/.X11-unix \
    && chmod 1777 /tmp/.X11-unix

# Vytvoøení uživatele container
RUN adduser --disabled-password --home /home/container container \
    && echo "container ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/container

# Nastavení pracovního adresáøe
USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

# Stažení kódu z privátního repozitáøe
ARG REPO_URL=https://github.com/bohemka-eu/cloud_obs.git
ARG COMMIT_SHA=1e66cb8
RUN --mount=type=secret,id=git_token \
    GIT_TOKEN=$(cat /run/secrets/git_token) && \
    git clone https://${GIT_TOKEN}@github.com/bohemka-eu/cloud_obs.git /tmp/repo \
    && cd /tmp/repo \
    && git checkout ${COMMIT_SHA} \
    && mv /tmp/repo/* /tmp/repo/.[!.]* /home/container/ 2>/dev/null || true \
    && rm -rf /tmp/repo

# Vytvoøení adresáøe data a výchozího uzivatele.json
RUN mkdir -p /home/container/data \
    && if [ ! -f "/home/container/data/uzivatele.json" ]; then \
        echo '{"users":[{"username":"admin","password":"Bohemkajede"}]}' > /home/container/data/uzivatele.json; \
    fi \
    && chmod 644 /home/container/data/uzivatele.json

# Fallback pro entrypoint.sh
RUN if [ ! -f "/home/container/entrypoint.sh" ]; then \
        echo '#!/bin/bash\n\
cd /home/container\n\
echo "Starting container in /home/container"\n\
echo "Environment: $(env)"\n\
mkdir -p /home/container/data\n\
if [ ! -f "/home/container/data/uzivatele.json" ]; then\n\
    echo "{\"users\":[{\"username\":\"admin\",\"password\":\"Bohemkajede\"}]}" > /home/container/data/uzivatele.json\n\
    chmod 644 /home/container/data/uzivatele.json\n\
fi\n\
echo "Starting Xvfb..."\n\
Xvfb :99 -screen 0 1920x1080x24 &\n\
XVFB_PID=$!\n\
sleep 1\n\
if ! kill -0 $XVFB_PID 2>/dev/null; then\n\
    echo "Error: Xvfb failed to start"\n\
    exit 1\n\
fi\n\
export DISPLAY=:99\n\
echo "Starting x11vnc..."\n\
x11vnc -display :99 -nopw -forever &\n\
echo "Starting websockify..."\n\
websockify --web /usr/share/novnc 6080 localhost:5900 &\n\
if [ -f "/home/container/bohemka-bot" ]; then\n\
    echo "Starting Bohemka Bot..."\n\
    /usr/local/bin/bohemka-bot --port 3001 --config /home/container/config.json 2>&1 | tee /home/container/bohemka-bot.log &\n\
fi\n\
echo "Starting Node.js server..."\n\
node /home/container/server.js &\n\
MODIFIED_STARTUP=$(eval echo "${STARTUP}" | sed -e "s/{{/${/g" -e "s/}}/}/g")\n\
echo "Modified startup command: ${MODIFIED_STARTUP}"\n\
exec ${MODIFIED_STARTUP:-/bin/bash}' > /home/container/entrypoint.sh; \
    fi \
    && chmod +x /home/container/entrypoint.sh

# Fallback pro start.sh
RUN if [ ! -f "/home/container/start.sh" ]; then \
        echo '#!/bin/bash\n\
echo "Running start.sh"\n\
exec /bin/bash' > /home/container/start.sh; \
        chmod +x /home/container/start.sh; \
    fi

# Instalace Node.js závislostí
RUN npm install --production

# Oprávnìní pro skripty
RUN chmod +x /home/container/start.sh /home/container/entrypoint.sh /home/container/install.sh 2>/dev/null || true

# Nastavení portù
EXPOSE 3000 4455 6080 5900

# Vstupní bod
CMD ["/bin/bash", "/home/container/entrypoint.sh"]