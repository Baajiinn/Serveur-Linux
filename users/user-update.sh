#!/bin/bash
set -euo pipefail

LOG="/var/log/user_update.log"
CONFIG="/etc/Scripts/config.cfg"

# Vérifie les droits root
if [[ $EUID -ne 0 ]]; then
    echo "Ce script doit être exécuté en tant que root" | tee -a "$LOG"
    exit 1
fi

# Vérifie la présence du fichier de config
if [ ! -f "$CONFIG" ]; then
    echo "Fichier de configuration introuvable : $CONFIG" | tee -a "$LOG"
    exit 1
fi

source "$CONFIG"

echo -e "\n=== Script de modification d’utilisateur ===" | tee -a "$LOG"

read -p "Nom de l'utilisateur à modifier : " OLDUSER

# Vérifie l'existence de l'utilisateur
if ! id "$OLDUSER" &>/dev/null; then
    echo "Utilisateur $OLDUSER introuvable." | tee -a "$LOG"
    exit 1
fi

echo -e "\n[1] Changer le mot de passe Linux ? (o/n)"
read -r CHANGE_PWD
if [[ "$CHANGE_PWD" =~ ^[Oo]$ ]]; then
    passwd "$OLDUSER"
    echo "[✓] Mot de passe Linux modifié." | tee -a "$LOG"
fi

echo -e "\n[2] Changer le mot de passe Samba ? (o/n)"
read -r CHANGE_SMB
if [[ "$CHANGE_SMB" =~ ^[Oo]$ ]]; then
    smbpasswd "$OLDUSER"
    echo "[✓] Mot de passe Samba modifié." | tee -a "$LOG"
fi

echo -e "\n[3] Changer le mot de passe MariaDB ? (o/n)"
read -r CHANGE_DB
if [[ "$CHANGE_DB" =~ ^[Oo]$ ]]; then
    DBUSER="dbuser_$OLDUSER"
    echo -n "Nouveau mot de passe MariaDB : "
    read -s NEWPASS
    echo

    mysql -uroot -prootpassword <<EOF
ALTER USER '$DBUSER'@'localhost' IDENTIFIED BY '$NEWPASS';
FLUSH PRIVILEGES;
EOF
    echo "[✓] Mot de passe MariaDB mis à jour." | tee -a "$LOG"
fi

echo -e "\n[4] Renommer complètement l'utilisateur (Linux + Samba + base de données + Apache) ? (o/n)"
read -r RENAME_USER
if [[ "$RENAME_USER" =~ ^[Oo]$ ]]; then
    read -p "Nouveau nom d'utilisateur : " NEWUSER

    # Apache
    if [ -f "/etc/httpd/conf.d/$OLDUSER.conf" ]; then
        mv "/etc/httpd/conf.d/$OLDUSER.conf" "/etc/httpd/conf.d/$NEWUSER.conf"
        sed -i "s/$OLDUSER/$NEWUSER/g" "/etc/httpd/conf.d/$NEWUSER.conf"
        echo "[✓] Fichier Apache renommé." | tee -a "$LOG"
    fi

    # Répertoire web
    if [ -d "/srv/web/$OLDUSER" ]; then
        mv "/srv/web/$OLDUSER" "/srv/web/$NEWUSER"
        chown -R "$NEWUSER":"$NEWUSER" "/srv/web/$NEWUSER" 2>/dev/null || true
        echo "[✓] Répertoire web renommé." | tee -a "$LOG"
    fi

    # Base de données
    OLDB="db_$OLDUSER"
    NEWDB="db_$NEWUSER"
    OLDDBUSER="dbuser_$OLDUSER"
    NEWDBUSER="dbuser_$NEWUSER"

    mysql -uroot -prootpassword <<EOF
RENAME TABLE $OLDB.* TO $NEWDB.*;
DROP USER IF EXISTS '$NEWDBUSER'@'localhost';
CREATE USER '$NEWDBUSER'@'localhost' IDENTIFIED BY '$(openssl rand -hex 6)';
GRANT ALL PRIVILEGES ON $NEWDB.* TO '$NEWDBUSER'@'localhost';
FLUSH PRIVILEGES;
EOF

    echo "[✓] Base MariaDB renommée + utilisateur recréé." | tee -a "$LOG"

    # Samba : supprimer ancien + créer nouveau
    smbpasswd -x "$OLDUSER"
    usermod -l "$NEWUSER" "$OLDUSER"
    groupmod -n "$NEWUSER" "$OLDUSER"
    mv "/home/$OLDUSER" "/home/$NEWUSER" || true
    usermod -d "/home/$NEWUSER" -m "$NEWUSER"
    smbpasswd -a "$NEWUSER"
    echo "[✓] Utilisateur renommé dans le système, Samba et base." | tee -a "$LOG"
fi

# Redémarrage des services critiques
systemctl restart httpd smb nmb

echo -e "\n Mise à jour terminée pour l'utilisateur." | tee -a "$LOG"