#!/bin/bash
set -euo pipefail

echo -e "\n[+] Début de la configuration de Fail2Ban"
echo -e "------------------------------------------\n"

LOG_FILE="/var/log/fail2ban-setup.log"
JAIL_LOCAL="/etc/fail2ban/jail.local"
SSHD_LOCAL="/etc/fail2ban/jail.d/sshd.local"

exec > >(tee -a "$LOG_FILE") 2>&1

# Installation de Fail2Ban si non installé
if ! command -v fail2ban-client &>/dev/null; then
    echo "[*] Installation de Fail2Ban..."
    dnf install -y epel-release
    dnf install -y fail2ban fail2ban-firewalld
else
    echo "[*] Fail2Ban est déjà installé."
fi

# Activation du service
echo "[*] Activation de Fail2Ban au démarrage"
systemctl enable --now fail2ban

# Configuration générale
echo "[*] Configuration du fichier $JAIL_LOCAL"
cat <<EOF > "$JAIL_LOCAL"
[DEFAULT]
bantime = 3600
findtime = 3600
maxretry = 3
EOF

# Configuration SSH spécifique
echo "[*] Configuration de la prison SSH dans $SSHD_LOCAL"
mkdir -p /etc/fail2ban/jail.d
cat <<EOF > "$SSHD_LOCAL"
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/secure
backend = systemd
EOF

# Vérification et redémarrage
echo "[*] Redémarrage de fail2ban..."
systemctl restart fail2ban

echo -e "\n[*] État de la prison SSH :"
fail2ban-client status sshd || echo "[!] Prison SSH non encore active, vérifier les logs."

echo -e "\nConfiguration de Fail2Ban terminée"
echo -e "------------------------------------------\n"