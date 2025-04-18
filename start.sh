#!/bin/bash
set -x
export XDG_RUNTIME_DIR=/run/user/$(id -u container)

# Use environment variables for ports
NODE_PORT=${NODE_PORT:-3000}
WEBSOCKIFY_PORT=${WEBSOCKIFY_PORT:-6080}
BOHEMKA_PORT=${BOHEMKA_PORT:-3001}
OBS_WS_PORT=${OBS_WS_PORT:-4455}
VNC_PORT=${VNC_PORT:-5900}

# Clean up old lock files
pkill -u container Xvfb || true
rm -f /tmp/.X99-lock /tmp/.X*-lock
mkdir -p /tmp/.X11-unix
chown container:container /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
echo "Starting Xvfb..."
Xvfb :99 -screen 0 1280x720x24 &
XVFB_PID=$!

# Wait for Xvfb
sleep 2
if ! ps -p $XVFB_PID > /dev/null; then
    echo "Error: Xvfb failed to start"
    exit 1
fi

# Start PulseAudio
pkill -u container pulseaudio || true
rm -rf /tmp/pulse-*
echo "Starting PulseAudio..."
pulseaudio --start &

# Configure OBS WebSocket
echo "Configuring OBS WebSocket on port $OBS_WS_PORT..."
mkdir -p /home/container/.config/obs-studio/plugin_config/obs-websocket
echo "{\"ServerEnabled\":true,\"ServerPort\":$OBS_WS_PORT,\"ServerPassword\":null}" > /home/container/.config/obs-studio/plugin_config/obs-websocket/settings.json
chmod -R 700 /home/container/.config/obs-studio

# Start OBS
pkill -u container obs || true
echo "Starting OBS..."
export DISPLAY=:99
obs --startstreaming --disable-studio-mode --verbose 2>&1 | tee /home/container/.config/obs-studio/logs/obs.log &
OBS_PID=$!

# Wait for OBS
sleep 2
if ! ps -p $OBS_PID > /dev/null; then
    echo "Error: OBS failed to start"
    exit 1
fi

# Start x11vnc
pkill -u container x11vnc || true
echo "Starting x11vnc on port $VNC_PORT..."
x11vnc -display :99 -forever -shared -nopw -noshm -xkb -rfbport "$VNC_PORT" -localhost 2>&1 | tee /home/container/x11vnc.log &
X11VNC_PID=$!

# Wait for x11vnc
sleep 2
if ! ps -p $X11VNC_PID > /dev/null; then
    echo "Error: x11vnc failed to start"
    cat /home/container/x11vnc.log
    exit 1
fi

# Start websockify
pkill -f "websockify.*$WEBSOCKIFY_PORT" || true
echo "Starting websockify on port $WEBSOCKIFY_PORT..."
websockify --web /opt/noVNC "$WEBSOCKIFY_PORT" localhost:"$VNC_PORT" 2>&1 | tee /home/container/websockify.log &
WEBSOCKIFY_PID=$!

# Wait for websockify
sleep 2
if ! ps -p $WEBSOCKIFY_PID > /dev/null; then
    echo "Error: websockify failed to start"
    cat /home/container/websockify.log
    exit 1
fi

# Start Bohemka Bot
pkill -u container bohemka-bot || true
echo "Starting Bohemka Bot on port $BOHEMKA_PORT..."
/usr/local/bin/bohemka-bot --port "$BOHEMKA_PORT" --config /home/container/config.json > /home/container/bohemka-bot.log 2>&1 &

# Start Node.js server
pkill -f "node /home/container/server.js" || true
echo "Starting Node.js server on port $NODE_PORT..."
exec node /home/container/server.js 2>&1 | tee /home/container/server.log