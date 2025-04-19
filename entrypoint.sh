#!/bin/bash
cd /home/container
echo "Starting container in /home/container"
echo "Environment: $(env)"

# Spustit install.sh
bash /home/container/install.sh

# Spustit start.sh
MODIFIED_STARTUP=$(eval echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo "Modified startup command: ${MODIFIED_STARTUP}"
exec ${MODIFIED_STARTUP:-bash /home/container/start.sh}