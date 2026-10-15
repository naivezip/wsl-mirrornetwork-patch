#!/usr/bin/env bash
# Helper script to configure WSL boot hook in /etc/wsl.conf
set -e

HOOK_CMD="/mnt/c/Windows/System32/schtasks.exe /run /tn DisableEthernetForwarding"
CONF_FILE="/etc/wsl.conf"

if [ "$EUID" -ne 0 ]; then
    echo "[-] Please run as root (sudo $0)"
    exit 1
fi

if [ -f "$CONF_FILE" ] && grep -q "DisableEthernetForwarding" "$CONF_FILE"; then
    echo "[✓] Hook already configured in $CONF_FILE"
    exit 0
fi

if [ ! -f "$CONF_FILE" ]; then
    cat << EOF > "$CONF_FILE"
[boot]
systemd=true
command="$HOOK_CMD"
EOF
    echo "[✓] Created $CONF_FILE and added boot hook."
else
    if grep -q '^\[boot\]' "$CONF_FILE"; then
        if grep -q 'command[[:space:]]*=' "$CONF_FILE"; then
            sed -i "/command[[:space:]]*=/ s|\"$|; $HOOK_CMD\"|" "$CONF_FILE"
            echo "[✓] Appended hook to existing boot command in $CONF_FILE"
        else
            sed -i "/^\[boot\]/a command=\"$HOOK_CMD\"" "$CONF_FILE"
            echo "[✓] Added boot command to [boot] section in $CONF_FILE"
        fi
    else
        cat << EOF >> "$CONF_FILE"

[boot]
systemd=true
command="$HOOK_CMD"
EOF
        echo "[✓] Appended [boot] section with hook to $CONF_FILE"
    fi
fi
