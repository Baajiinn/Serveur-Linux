#!/bin/bash
set -euo pipefail
trap '' PIPE  # ignore Broken pipe

# === Variables ===
SCRIPTS_DIR="/etc/Scripts/scripts"      # Dossier contenant tes scripts
BACKUP_DIR="/var/backups/server"        # Dossier de backup
LOG_FILE="/var/log/auto-backup.log"
CRON_FILE="/etc/cron.d/auto-backup"
DATE=$(date '+%Y-%m-%d_%H-%M-%S')
ARCHIVE_NAME="backup_$DATE.tar.gz"
REPO_URL="https://github.com/sormy/aws-ec2-rsnapshot.git"
REPO_DIR="aws-ec2-rsnapshot"
SYMLINK_SRC="/srv/aws-ec2-rsnapshot/aws-ec2-rsnapshot.sh"
SYMLINK_DST="/usr/local/bin/aws-ec2-rsnapshot"

# === Préparation ===
echo "[*] Lancement du script de backup : $DATE" | tee -a "$LOG_FILE"

# Installer aws-ec2-rsnapshot si non présent
if ! command -v aws-ec2-rsnapshot &>/dev/null; then
    echo "[+] aws-ec2-rsnapshot non trouvé, installation…" | tee -a "$LOG_FILE"

    # Installer git si nécessaire
    if ! command -v git &>/dev/null; then
        echo "[*] git non trouvé, installation via dnf" | tee -a "$LOG_FILE"
        sudo dnf install -y git | tee -a "$LOG_FILE"
    fi

    # Cloner seulement si le répertoire n'existe pas
    if [ ! -d "$REPO_DIR" ]; then
        git clone "$REPO_URL" "$REPO_DIR" | tee -a "$LOG_FILE"
    else
        echo "[=] Dossier '$REPO_DIR' existe déjà, clone ignoré." | tee -a "$LOG_FILE"
    fi

    # Créer le lien symbolique uniquement s'il n'existe pas
    if [ ! -L "$SYMLINK_DST" ]; then
        sudo ln -s "$SYMLINK_SRC" "$SYMLINK_DST"
        echo "[+] Lien symbolique créé : $SYMLINK_DST -> $SYMLINK_SRC" | tee -a "$LOG_FILE"
    else
        echo "[=] Lien $SYMLINK_DST existe déjà, création ignorée." | tee -a "$LOG_FILE"
    fi
else
    echo "[=] aws-ec2-rsnapshot est déjà disponible." | tee -a "$LOG_FILE"
fi

# Créer les dossiers nécessaires
mkdir -p "$BACKUP_DIR/logs" "$BACKUP_DIR/archives"

# === Parcourir les scripts et vérifier les logs ===
echo "[*] Vérification des scripts dans $SCRIPTS_DIR" | tee -a "$LOG_FILE"

for script in "$SCRIPTS_DIR"*/*.sh; do
    script_name=$(basename "$script")

    if grep -Eq 'tee|logger|/var/log/|>>' "$script"; then
        echo "[=] $script_name est déjà journalisé. Ignoré." | tee -a "$LOG_FILE"
    else
        echo "[!] $script_name ne semble pas journalisé. Exécution avec redirection." | tee -a "$LOG_FILE"
        bash "$script" >> "$BACKUP_DIR/logs/${script_name%.sh}_$DATE.log" 2>&1
    fi
done

# === Archive des logs ===
tar -czf "$BACKUP_DIR/archives/$ARCHIVE_NAME" -C "$BACKUP_DIR/logs" .
echo "[+] Archive créée : $ARCHIVE_NAME" | tee -a "$LOG_FILE"

# Nettoyage : logs >30j, archives >60j
find "$BACKUP_DIR/logs/"    -type f -mtime +30 -delete
find "$BACKUP_DIR/archives/" -type f -mtime +60 -delete

# === Configuration CRON ===
if [ ! -f "$CRON_FILE" ]; then
    echo "[*] Création de la tâche cron." | tee -a "$LOG_FILE"
    echo "0 2 * * * root /bin/bash $SCRIPTS_DIR/auto-backup.sh" > "$CRON_FILE"
    chmod 644 "$CRON_FILE"
    echo "[+] Cron programmé à 02:00 tous les jours." | tee -a "$LOG_FILE"
else
    echo "[=] Cron déjà configuré." | tee -a "$LOG_FILE"
fi

echo "Sauvegarde complète terminée à $(date)" | tee -a "$LOG_FILE"