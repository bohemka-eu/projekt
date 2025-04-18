# ----------------------------------
# Pterodactyl OBS Control Panel Dockerfile
# Environment: Node.js + OBS + noVNC
# Minimum Panel Version: 1.0.0
# Uses specific commit from public repository
# ----------------------------------
FROM alpine:3.18

LABEL maintainer="Bohemka <sprava_serveru@bohemka.eu>"

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

# Instalace noVNC
RUN mkdir -p /usr/share/novnc \
    && curl -L https://github.com/novnc/noVNC/archive/refs/tags/v1.5.0.tar.gz | tar -xz -C /usr/share/novnc --strip-components=1 \
    && ln -s /usr/share/novnc/vnc.html /usr/share/novnc/index.html

# Nastavení /tmp/.X11-unix
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

# Stažení kódu z veøejného repozitáøe
ARG REPO_URL=https://github.com/bohemka-eu/projekt.git
ARG COMMIT_SHA=358e595
RUN git clone ${REPO_URL} /tmp/repo && \
    cd /tmp/repo && \
    git checkout ${COMMIT_SHA} && \
    echo "Debug: Content of /tmp/repo before move" && \
    ls -laR /tmp/repo && \
    mv /tmp/repo/* /tmp/repo/.[!.]* /home/container/ 2>/dev/null || true && \
    echo "Debug: Content of /home/container after move" && \
    ls -la /home/container && \
    rm -rf /tmp/repo

# Vytvoøení adresáøe data a výchozího uzivatele.json
RUN mkdir -p /home/container/data \
    && if [ ! -f "/home/container/data/uzivatele.json" ]; then \
        echo '{"users":[{"username":"admin","password":"Bohemkajede"}]}' > /home/container/data/uzivatele.json; \
    fi \
    && chmod 644 /home/container/data/uzivatele.json

# Fallback pro package.json
RUN if [ ! -f "/home/container/package.json" ]; then \
        echo '{"name":"cloud-obs","version":"1.0.0","description":"Cloud OBS control panel","main":"server.js","scripts":{"start":"node server.js"},"dependencies":{"bcrypt":"^5.1.1","cookie-parser":"^1.4.6","dotenv":"^16.4.5","express":"^4.19.2","http-proxy-middleware":"^2.0.6"}}' > /home/container/package.json; \
    fi

# Instalace Node.js závislostí
RUN npm install --production

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
Xvfb :99 -screen 0 1280x720x24 &\n\
XVFB_PID=$!\n\
sleep 2\n\
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
set -x\n\
export XDG_RUNTIME_DIR=/run/user/$(id -u container)\n\
NODE_PORT=${NODE_PORT:-3000}\n\
WEBSOCKIFY_PORT=${WEBSOCKIFY_PORT:-6080}\n\
BOHEMKA_PORT=${BOHEMKA_PORT:-3001}\n\
OBS_WS_PORT=${OBS_WS_PORT:-4455}\n\
VNC_PORT=${VNC_PORT:-5900}\n\
pkill -u container Xvfb || true\n\
rm -f /tmp/.X99-lock /tmp/.X*-lock\n\
echo "Starting Xvfb..."\n\
Xvfb :99 -screen 0 1280x720x24 &\n\
XVFB_PID=$!\n\
sleep 2\n\
if ! kill -0 $XVFB_PID 2>/dev/null; then\n\
    echo "Error: Xvfb failed to start"\n\
    exit 1\n\
fi\n\
echo "Starting PulseAudio..."\n\
pkill -u container pulseaudio || true\n\
rm -rf /tmp/pulse-*\n\
pulseaudio --start &\n\
echo "Configuring OBS WebSocket on port $OBS_WS_PORT..."\n\
mkdir -p /home/container/.config/obs-studio/plugin_config/obs-websocket\n\
echo "{\"ServerEnabled\":true,\"ServerPort\":$OBS_WS_PORT,\"ServerPassword\":null}" > /home/container/.config/obs-studio/plugin_config/obs-websocket/settings.json\n\
chmod -R 700 /home/container/.config/obs-studio\n\
echo "Starting OBS..."\n\
export DISPLAY=:99\n\
pkill -u container obs || true\n\
obs --startstreaming --disable-studio-mode --verbose 2>&1 | tee /home/container/.config/obs-studio/logs/obs.log &\n\
OBS_PID=$!\n\
sleep 2\n\
if ! kill -0 $OBS_PID 2>/dev/null; then\n\
    echo "Error: OBS failed to start"\n\
    exit 1\n\
fi\n\
echo "Starting x11vnc on port $VNC_PORT..."\n\
pkill -u container x11vnc || true\n\
x11vnc -display :99 -forever -shared -nopw -noshm -xkb -rfbport "$VNC_PORT" -localhost 2>&1 | tee /home/container/x11vnc.log &\n\
X11VNC_PID=$!\n\
sleep 2\n\
if ! kill -0 $X11VNC_PID 2>/dev/null; then\n\
    echo "Error: x11vnc failed to start"\n\
    cat /home/container/x11vnc.log\n\
    exit 1\n\
fi\n\
echo "Starting websockify on port $WEBSOCKIFY_PORT..."\n\
pkill -f "websockify.*$WEBSOCKIFY_PORT" || true\n\
websockify --web /usr/share/novnc "$WEBSOCKIFY_PORT" localhost:"$VNC_PORT" 2>&1 | tee /home/container/websockify.log &\n\
WEBSOCKIFY_PID=$!\n\
sleep 2\n\
if ! kill -0 $WEBSOCKIFY_PID 2>/dev/null; then\n\
    echo "Error: websockify failed to start"\n\
    cat /home/container/websockify.log\n\
    exit 1\n\
fi\n\
pkill -u container bohemka-bot || true\n\
if [ -f "/home/container/bohemka-bot" ]; then\n\
    echo "Starting Bohemka Bot on port $BOHEMKA_PORT..."\n\
    /usr/local/bin/bohemka-bot --port "$BOHEMKA_PORT" --config /home/container/config.json 2>&1 | tee /home/container/bohemka-bot.log &\n\
fi\n\
echo "Starting Node.js server on port $NODE_PORT..."\n\
pkill -f "node /home/container/server.js" || true\n\
exec node /home/container/server.js 2>&1 | tee /home/container/server.log' > /home/container/start.sh; \
        chmod +x /home/container/start.sh; \
    fi

# Fallback pro server.js
RUN if [ ! -f "/home/container/server.js" ]; then \
        echo 'const express = require("express");\n\
const app = express();\n\
app.get("/", (req, res) => res.send("OBS Control Panel"));\n\
app.listen(3000, () => console.log("Server running on port 3000"));' > /home/container/server.js; \
    fi

# Oprávnìní pro skripty
RUN chmod +x /home/container/start.sh /home/container/entrypoint.sh /home/container/install.sh /home/container/server.js 2>/dev/null || true

# Nastavení portù
EXPOSE 3000 4455 6080 5900

# Vstupní bod
CMD ["/bin/bash", "/home/container/entrypoint.sh"]