#!/bin/bash
set -euo pipefail

LOG="/var/log/user_del.log"
CONFIG="/etc/Scripts/config.cfg"

# Vérifie les privilèges root
if [[ $EUID -ne 0 ]]; then
    echo "Ce script doit être exécuté en tant que root." | tee -a "$LOG"
    exit 1
fi

# Vérifie la config
if [ ! -f "$CONFIG" ]; then
    echo "Fichier de configuration introuvable : $CONFIG" | tee -a "$LOG"
    exit 1
fi

source "$CONFIG"

# Vérifie le paramètre utilisateur
if [ -z "${1:-}" ]; then
    echo "Usage: $0 <nom_utilisateur>" | tee -a "$LOG"
    exit 1
fi

USER="$1"
HOMEDIR="/srv/web/$USER"
DBNAME="db_$USER"
DBUSER="dbuser_$USER"
USERLIST="/etc/vsftpd/user_list"

echo -e "\n=== Suppression de l'utilisateur $USER ===" | tee -a "$LOG"

# 1. Supprime le VirtualHost Apache
VHOST_FILE="/etc/httpd/conf.d/$USER.conf"
if [ -f "$VHOST_FILE" ]; then
    rm -f "$VHOST_FILE"
    echo "[+] VirtualHost Apache supprimé : $VHOST_FILE" | tee -a "$LOG"
fi

# 2. Supprime la base de données MariaDB et l’utilisateur SQL
mysql -uroot -prootpassword <<EOF
DROP DATABASE IF EXISTS $DBNAME;
DROP USER IF EXISTS '$DBUSER'@'localhost';
FLUSH PRIVILEGES;
EOF
echo "[+] Base MariaDB $DBNAME et utilisateur $DBUSER supprimés." | tee -a "$LOG"

# 3. Supprime le partage Samba
sed -i "/^\[$USER\]/,/^$/d" /etc/samba/smb.conf
if pdbedit -L | grep -q "^$USER:"; then
    smbpasswd -x "$USER"
    echo "[+] Utilisateur Samba $USER supprimé." | tee -a "$LOG"
fi

# 4. Supprime de vsFTPD
if grep -q "^$USER\$" "$USERLIST"; then
    sed -i "/^$USER$/d" "$USERLIST"
    echo "[+] Utilisateur $USER supprimé de vsFTPD." | tee -a "$LOG"
fi

# 5. Supprime le dossier web
if [ -d "$HOMEDIR" ]; then
    rm -rf "$HOMEDIR"
    echo "[+] Répertoire web $HOMEDIR supprimé." | tee -a "$LOG"
fi

# 6. Supprime l’utilisateur système
if id "$USER" &>/dev/null; then
    userdel -r "$USER" 2>/dev/null || true
    echo "[+] Utilisateur système $USER supprimé." | tee -a "$LOG"
else
    echo "[=] Utilisateur système $USER introuvable." | tee -a "$LOG"
fi

# 7. Redémarre les services pour appliquer les changements
systemctl restart httpd smb nmb

echo "L'utilisateur $USER a été complètement supprimé." | tee -a "$LOG"