#!/bin/bash
set -euo pipefail

echo -e "\n=== Installation & Configuration de ClamAV sur Amazon Linux 2023 ===\n"

WORKDIR="$HOME/clamav-install"
REPO_URL="https://dl.fedoraproject.org/pub/fedora/linux/releases/38/Everything/x86_64/os/"
LOG_DIR="/var/log/clamav"
LOG_FILE="$LOG_DIR/clamav-scan.log"

# 1. Préparation
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[INFO] Installation de dnf-utils pour gérer les dépôts..."
sudo dnf install -y dnf-utils

echo "[INFO] Ajout temporaire du dépôt Fedora 38..."
sudo dnf config-manager --add-repo "$REPO_URL"

echo "[INFO] Téléchargement des paquets ClamAV et dépendances..."
dnf download --resolve clamav clamav-update

echo "[INFO] Installation des paquets téléchargés..."
sudo dnf install -y ./*.rpm

echo "[INFO] Nettoyage temporaire..."
cd ~
rm -rf "$WORKDIR"

# 2. Vérification
command -v clamscan >/dev/null || { echo "[ERREUR] clamscan non disponible après installation."; exit 1; }
command -v freshclam >/dev/null || { echo "[ERREUR] freshclam non disponible après installation."; exit 1; }

echo "[INFO] Version installée : $(clamscan --version)"

# 3. Configuration des logs
echo "[INFO] Configuration des journaux..."
sudo mkdir -p "$LOG_DIR"
sudo touch "$LOG_FILE"
sudo chown ec2-user:ec2-user "$LOG_DIR" "$LOG_FILE"

# 4. Installation et activation du service cron
if ! rpm -q cronie >/dev/null; then
    echo "[INFO] Installation de cronie (cron)..."
    sudo dnf install -y cronie
fi

echo "[INFO] Activation et démarrage du service cron..."
sudo systemctl enable --now crond

# 5. Tâches cron
echo "[INFO] Ajout des tâches cron : scan et mise à jour"

CRON_SCAN="0 2 * * * /usr/bin/clamscan -ri / >> $LOG_FILE"
CRON_UPDATE="0 1 * * * /usr/bin/freshclam >> /var/log/clamav/freshclam.log 2>&1"

# Supprimer les lignes existantes si elles existent
(crontab -l 2>/dev/null | grep -v -F "clamscan -ri /" | grep -v -F "freshclam") | crontab -

# Ajouter les nouvelles
(crontab -l 2>/dev/null; echo "$CRON_SCAN"; echo "$CRON_UPDATE") | crontab -

echo -e "\n[SUCCESS] ClamAV est installé et configuré !"
echo "[Tâches cron prévues]"
echo "   - Mise à jour des définitions à 1h00"
echo "   - Scan complet à 2h00"
echo "[Logs]"
echo "   - Scan : $LOG_FILE"
echo "   - Update : /var/log/clamav/freshclam.log"