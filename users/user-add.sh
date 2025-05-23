#!/usr/bin/env bash
set -euo pipefail

# Protection contre exécution récursive
[[ "${USER_ADD_RUNNING:-}" == "1" ]] && exit 0
export USER_ADD_RUNNING=1

LOG="/var/log/user_add.log"
CONFIG="/etc/Scripts/config.cfg"

# Log niveau de shell
echo "Niveau de shell actuel (SHLVL) : $SHLVL" | tee -a "$LOG"

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
DBPASS=$(openssl rand -hex 8)
USERLIST="/etc/vsftpd/user_list"
MAILDIR="/home/$USER/Maildir"

# === 1. Création utilisateur ===
echo -e "\n=== Ajout de l'utilisateur $USER ===" | tee -a "$LOG"
if ! id "$USER" &>/dev/null; then
    useradd -m -s /bin/bash "$USER"
    echo "$USER:$USER" | chpasswd
    echo "[+] Utilisateur $USER créé avec mot de passe : $USER" | tee -a "$LOG"
else
    echo "[=] Utilisateur $USER existe déjà." | tee -a "$LOG"
fi

# === 2. Dossier Web ===
mkdir -p "$HOMEDIR"
echo "<?php echo '<h1>Bienvenue $USER</h1>'; ?>" > "$HOMEDIR/index.php"
chown -R apache:apache "$HOMEDIR"
chmod -R 755 "$HOMEDIR"
echo "[+] Dossier web $HOMEDIR configuré." | tee -a "$LOG"

# === 3. VirtualHost Apache ===
cat <<EOF > "/etc/httpd/conf.d/$USER.conf"
<VirtualHost *:80>
    ServerName $USER.$SERVERNAME.$DOMAIN
    Redirect permanent / https://$USER.$SERVERNAME.$DOMAIN/
</VirtualHost>

<VirtualHost _default_:443>
    ServerName $USER.$SERVERNAME.$DOMAIN
    DocumentRoot /srv/web/$USER
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/httpd-selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/certs/httpd-selfsigned.key
</VirtualHost>
EOF
echo "[+] VirtualHost Apache configuré pour $USER." | tee -a "$LOG"

# === 4. Base de données ===
mysql -uroot -prootpassword <<EOF
CREATE DATABASE IF NOT EXISTS $DBNAME;
CREATE USER IF NOT EXISTS '$DBUSER'@'localhost' IDENTIFIED BY '$DBPASS';
GRANT ALL PRIVILEGES ON $DBNAME.* TO '$DBUSER'@'localhost';
FLUSH PRIVILEGES;
EOF
echo "[+] Base $DBNAME / Utilisateur $DBUSER créé." | tee -a "$LOG"
echo "[+] Mot de passe SQL : $DBPASS" | tee -a "$LOG"

# === 5. Samba ===
mkdir -p "$HOMEDIR"
chown "$USER:$USER" "$HOMEDIR"
chmod 700 "$HOMEDIR"
if ! pdbedit -L | grep -q "^$USER:"; then
    (echo "$USER"; echo "$USER") | smbpasswd -s -a "$USER"
    echo "[+] Utilisateur Samba ajouté." | tee -a "$LOG"
else
    echo "[=] Utilisateur Samba existe déjà." | tee -a "$LOG"
fi

if ! grep -q "^\[$USER\]" /etc/samba/smb.conf; then
cat <<EOF >> /etc/samba/smb.conf

[$USER]
   path = /srv/web/$USER
   writable = yes
   guest ok = no
   valid users = $USER
   inherit permissions = yes
EOF
    echo "[+] Partage Samba ajouté." | tee -a "$LOG"
fi

# === 6. vsFTPD ===
mkdir -p "$HOMEDIR"
chown "$USER:$USER" "$HOMEDIR"
chmod 755 "$HOMEDIR"
if ! grep -q "^$USER$" "$USERLIST"; then
    echo "$USER" >> "$USERLIST"
    echo "[+] Utilisateur FTP ajouté à $USERLIST." | tee -a "$LOG"
fi

# === 7. Maildir, Dovecot/Postfix ===
mkdir -p "$MAILDIR"
chown -R "$USER:$USER" "$MAILDIR"
chmod -R 700 "$MAILDIR"

# Postfix/Dovecot utilisent création automatique de Maildir si configuré dans main.cf et 10-mail.conf
# Si non fait, tu dois avoir :
# home_mailbox = Maildir/
# dans /etc/postfix/main.cf
# mail_location = maildir:~/Maildir
# dans /etc/dovecot/conf.d/10-mail.conf

echo "[+] Maildir initialisé pour $USER." | tee -a "$LOG"

# === 8. SELinux & redémarrage services ===
semanage fcontext -a -e /var/www /srv/web || true
restorecon -Rv /srv/web &>/dev/null

systemctl restart httpd smb nmb dovecot postfix || true

echo "[+] Utilisateur $USER totalement configuré." | tee -a "$LOG"