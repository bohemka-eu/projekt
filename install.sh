#!/bin/bash
cd /home/container
echo "Checking files..."

# Kopírování souborù z image, pokud svazek je prázdný
if [ ! -f "start.sh" ] || [ ! -f "entrypoint.sh" ] || [ ! -f "server.js" ]; then
    echo "Copying files from image..."
    cp -r /home/container-template/* /home/container/ 2>/dev/null
    cp -r /home/container-template/. /home/container/ 2>/dev/null
fi

# Nastavení oprávnìní
echo "Setting permissions..."
chmod +x start.sh entrypoint.sh 2>/dev/null || echo "Warning: Scripts not found"
chown -R container:container /home/container

# Inicializace adresáøù
echo "Initializing directories..."
mkdir -p .config/obs-studio/logs data
chown -R container:container .config data
chmod -R 700 .config data

# Kontrola souborù
echo "Verifying key files..."
for file in start.sh entrypoint.sh server.js config.json data/uzivatele.json; do
    if [ ! -f "$file" ]; then
        echo "Error: $file is missing!"
        exit 1
    fi
done

echo "Installation complete."