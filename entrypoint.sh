#!/bin/bash

cd /home/container

# Výpis prostøedí pro debug
echo "Starting container in /home/container"
echo "Environment: $(env)"

# Nastavení X11
mkdir -p /tmp/.X11-unix
chown root:root /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

# Spuštìní Xvfb pro noVNC
echo "Starting Xvfb..."
Xvfb :99 -screen 0 1920x1080x24 &
XVFB_PID=$!
sleep 1
if ! kill -0 $XVFB_PID 2>/dev/null; then
    echo "Error: Xvfb failed to start - again"
    exit 1
fi
export DISPLAY=:99

# Spuštìní x11vnc
echo "Starting x11vnc..."
x11vnc -display :99 -nopw -forever &

# Spuštìní websockify pro noVNC
echo "Starting websockify..."
websockify --web /usr/share/novnc 6080 localhost:5900 &

# Spuštìní Bohemka Bot
if [ -f "/home/container/bohemka-bot" ]; then
    echo "Starting Bohemka Bot..."
    /usr/local/bin/bohemka-bot --port 3001 --config /home/container/config.json 2>&1 | tee /home/container/bohemka-bot.log &
fi

# Spuštìní Node.js serveru
echo "Starting Node.js server..."
node /home/container/server.js &

# Nahrazení promìnných v STARTUP
MODIFIED_STARTUP=$(eval echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo "Modified startup command: ${MODIFIED_STARTUP}"

# Spuštìní hlavního pøíkazu
exec ${MODIFIED_STARTUP:-/bin/bash}