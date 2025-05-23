#!/bin/bash
set -euo pipefail

echo -e "\n[*] Début de la sécurisation SSH avec Fail2ban\n"

# === VARIABLES ===
SSH_CONFIG="/etc/ssh/sshd_config"
JAIL_LOCAL="/etc/fail2ban/jail.local"
SSHD_JAIL="/etc/fail2ban/jail.d/sshd.local"
IGNOREIP="10.42.0.0/16 127.0.0.1"
BAN_TIME="3600"
FIND_TIME="3600"
MAX_RETRY="3"

# === INSTALLATION DES DÉPENDANCES ===
dnf install -y fail2ban

# === CONFIGURATION fail2ban ===
echo "[*] Configuration du fichier $JAIL_LOCAL"
cat > "$JAIL_LOCAL" <<EOF
[DEFAULT]
ignoreip = $IGNOREIP
bantime = ${BAN_TIME}s
findtime = ${FIND_TIME}s
maxretry = $MAX_RETRY
backend = systemd
EOF

chmod 644 "$JAIL_LOCAL"
chown root:root "$JAIL_LOCAL"

# === CONFIGURATION DE LA PRISON SSH ===
echo "[*] Configuration du fichier $SSHD_JAIL"
cat > "$SSHD_JAIL" <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/secure
bantime = ${BAN_TIME}s
findtime = ${FIND_TIME}s
maxretry = $MAX_RETRY
EOF

chmod 644 "$SSHD_JAIL"
chown root:root "$SSHD_JAIL"

# === AJUSTEMENTS DU SERVICE SSH ===
echo "[*] Vérification de la configuration SSH"

# Désactiver root login et renforcer SSH (optionnel mais recommandé)
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$SSH_CONFIG"
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG"
sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSH_CONFIG"

# Redémarrage du service SSH
systemctl restart sshd
echo "[+] Service SSH redémarré avec configuration renforcée"

# === ACTIVATION fail2ban ===
echo "[*] Activation de fail2ban"
systemctl enable --now fail2ban
systemctl restart fail2ban

# === STATUT FAIL2BAN ===
echo "[*] Vérification de la prison SSH"
fail2ban-client status sshd || echo "[!] La prison SSH n'est pas active ou mal configurée."

echo -e "\n[+] Configuration de Fail2ban terminée avec succès\n"