#!/bin/bash
cd /home/container
echo "Checking files..."

# Inicializace adresáøù
echo "Initializing directories..."
mkdir -p .config/obs-studio/logs data
chown -R container:container .config data
chmod -R 700 .config data

# Nastavení oprávnìní
echo "Setting permissions..."
chmod +x start.sh entrypoint.sh server.js 2>/dev/null || echo "Warning: Scripts not found"
chown -R container:container /home/container

# Kontrola souborù
echo "Verifying key files..."
for file in start.sh entrypoint.sh server.js data/uzivatele.json; do
    if [ ! -f "$file" ]; then
        echo "Error: $file is missing!"
        exit 1
    fi
done

echo "Installation complete."