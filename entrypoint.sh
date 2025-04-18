#!/bin/bash
cd /home/container
echo "Starting container in /home/container"
echo "Environment: $(env)"
mkdir -p /home/container/data
if [ ! -f "/home/container/data/uzivatele.json" ]; then
    echo "{\"users\":[{\"username\":\"admin\",\"password\":\"Bohemkajede\"}]}" > /home/container/data/uzivatele.json
    chmod 644 /home/container/data/uzivatele.json
fi
echo "Starting Xvfb..."
Xvfb :99 -screen 0 1280x720x24 &
XVFB_PID=$!
sleep 2
if ! kill -0 $XVFB_PID 2>/dev/null; then
    echo "Error: Xvfb failed to start"
    exit 1
fi
export DISPLAY=:99
echo "Starting x11vnc..."
x11vnc -display :99 -nopw -forever &
echo "Starting websockify..."
websockify --web /usr/share/novnc 6080 localhost:5900 &
if [ -f "/home/container/bohemka-bot" ]; then
    echo "Starting Bohemka Bot..."
    /usr/local/bin/bohemka-bot --port 3001 --config /home/container/config.json 2>&1 | tee /home/container/bohemka-bot.log &
fi
echo "Starting Node.js server..."
node /home/container/server.js &
MODIFIED_STARTUP=$(eval echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo "Modified startup command: ${MODIFIED_STARTUP}"
exec ${MODIFIED_STARTUP:-/bin/bash}