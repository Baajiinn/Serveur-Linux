#!/bin/bash
# Fichier : vsftpd_setup.sh
# Description : Script modulaire pour configurer un serveur FTP sécurisé avec VSFTPD sur Amazon Linux 2023 (AWS)

set -e  # Stoppe le script en cas d'erreur

# --------------------
# FICHIER DE CONFIGURATION
# --------------------
CONFIG_FILE="/etc/Scripts/config.cfg"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Fichier de configuration introuvable : $CONFIG_FILE"
  exit 1
fi
source "$CONFIG_FILE"

# --------------------
# MODULE 1 : INSTALLATION DE VSFTPD
# --------------------
echo "[1/5] Installation de vsftpd..."
sudo dnf install -y vsftpd
sudo systemctl enable vsftpd

# --------------------
# MODULE 2 : CONFIGURATION SSL
# --------------------
echo "[2/5] Génération certificat SSL..."
SSL_CERT="/etc/pki/tls/certs/vsftpd.pem"
if [ ! -f "$SSL_CERT" ]; then
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$SSL_CERT" -out "$SSL_CERT" \
    -subj "/C=BE/ST=AWS/L=Cloud/O=Linux/OU=IT/CN=ftp.$DOMAIN"
fi

# --------------------
# MODULE 3 : CONFIGURATION VSFTPD
# --------------------
echo "[3/5] Configuration de /etc/vsftpd/vsftpd.conf..."
BACKUP_FILE="/etc/vsftpd/vsftpd.conf.bak"
sudo cp /etc/vsftpd/vsftpd.conf "$BACKUP_FILE"

# Écriture propre du nouveau fichier de conf
sudo tee /etc/vsftpd/vsftpd.conf > /dev/null <<EOF
listen=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
chroot_local_user=YES
allow_writeable_chroot=YES
userlist_enable=YES
userlist_deny=NO
userlist_file=/etc/vsftpd/user_list
pam_service_name=vsftpd
rsa_cert_file=$SSL_CERT
ssl_enable=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
allow_anon_ssl=NO
pasv_enable=YES
pasv_min_port=60000
pasv_max_port=61000
local_root=/home/$PRIMARYUSER
user_sub_token=$PRIMARYUSER
EOF

# --------------------
# MODULE 4 : FICHIERS DE SÉCURITÉ
# --------------------
echo "[4/5] Configuration des fichiers de sécurité..."

# ftpusers (interdits)
echo -e "root\nnobody\n" | sudo tee /etc/vsftpd/ftpusers > /dev/null

# user_list (seuls autorisés)
echo "$PRIMARYUSER" | sudo tee /etc/vsftpd/user_list > /dev/null

# chroot_list (non utilisé mais propre)
sudo touch /etc/vsftpd/chroot_list

# --------------------
# MODULE 5 : CONFIGURATION UTILISATEUR ET DOSSIERS
# --------------------
echo "[5/5] Création du dossier FTP..."
sudo mkdir -p /srv/web/$PRIMARYUSER
sudo chown $PRIMARYUSER:$PRIMARYUSER /srv/web/$PRIMARYUSER
sudo chmod 755 /srv/web/$PRIMARYUSER

# Ajouter automatiquement l'utilisateur au fichier user_list s'il n'y est pas déjà
if ! grep -q "^$PRIMARYUSER$" /etc/vsftpd/user_list; then
    echo "$PRIMARYUSER" | sudo tee -a /etc/vsftpd/user_list > /dev/null
    echo "Utilisateur $PRIMARYUSER ajouté à /etc/vsftpd/user_list."
else
    echo "Utilisateur $PRIMARYUSER déjà présent dans /etc/vsftpd/user_list."
fi


# --------------------
# LANCEMENT DU SERVICE
# --------------------
echo "Redémarrage de VSFTPD..."
sudo systemctl restart vsftpd


###############################################################################
# Configuration de Fail2Ban pour vsftpd
###############################################################################

# Variables
JAIL_LOCAL="/etc/fail2ban/jail.local"
VSFTPD_JAIL="/etc/fail2ban/jail.d/vsftpd.local"
IGNOREIP="10.42.0.0/16 127.0.0.1"
BAN_TIME="3600"     # Durée du bannissement (en secondes)
FIND_TIME="3600"    # Fenêtre de recherche des échecs (en secondes)
MAX_RETRY="3"       # Nombre max d’essais avant bannissement

# 1) Installation de fail2ban si nécessaire
echo "[*] Installation de fail2ban…"
sudo dnf install -y fail2ban

# 2) Configuration globale (jail.local)
echo "[*] Écriture de la configuration globale dans $JAIL_LOCAL"
sudo tee "$JAIL_LOCAL" > /dev/null <<EOF
[DEFAULT]
ignoreip = $IGNOREIP
bantime  = ${BAN_TIME}s
findtime = ${FIND_TIME}s
maxretry = $MAX_RETRY
backend  = systemd
EOF
sudo chmod 644 "$JAIL_LOCAL"
sudo chown root:root "$JAIL_LOCAL"

# 3) Configuration de la prison vsftpd
echo "[*] Écriture de la prison vsftpd dans $VSFTPD_JAIL"
sudo tee "$VSFTPD_JAIL" > /dev/null <<EOF
[vsftpd]
enabled  = true
port     = ftp,ftp-data,ftps,ftps-data
protocol = tcp
filter   = vsftpd
logpath  = /var/log/vsftpd.log
maxretry = $MAX_RETRY
bantime  = ${BAN_TIME}s
findtime = ${FIND_TIME}s
EOF
sudo chmod 644 "$VSFTPD_JAIL"
sudo chown root:root "$VSFTPD_JAIL"

# 4) S’assurer que le filtre existe
if [ ! -f /etc/fail2ban/filter.d/vsftpd.conf ]; then
  echo "[*] Création du filtre vsftpd par défaut"
  sudo tee /etc/fail2ban/filter.d/vsftpd.conf > /dev/null <<'EOF'
# Fail2Ban filter for vsftpd
[Definition]
failregex = ^%(__prefix_line)s(?:error: )?pam_unix\(vsftpd:auth\): authentication failure;.*rhost=<HOST>\s*$
            ^%(__prefix_line)svsftpd\[\d+\]: FAIL LOGIN: Client "<HOST>"$
            ^%(__prefix_line)svsftpd\[\d+\]: FAIL USER: Client "<HOST>", User .+$
ignoreregex =
EOF
fi

# 5) Activation et démarrage
echo "[*] Activation de fail2ban et redémarrage du service"
sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban

# 6) Vérification de l’état de la prison vsftpd
echo "[*] Statut de la prison vsftpd"
sudo fail2ban-client status vsftpd || {
  echo "[!] Échec de l’activation de la prison vsftpd"
  exit 1
}

echo "[+] Fail2Ban configuré pour vsftpd avec succès !"


# --------------------
# FIN
# --------------------
echo "\nConfiguration VSFTPD terminée avec succès sur Amazon Linux 2023."
echo "Fichier de conf sauvegardé ici : $BACKUP_FILE"
echo "Seul l'utilisateur suivant est autorisé en FTP : $PRIMARYUSER"