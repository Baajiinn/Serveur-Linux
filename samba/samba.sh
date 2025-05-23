#!/bin/bash

# === VÉRIFICATION ROOT ===
if [ "$EUID" -ne 0 ]; then
  echo " Ce script doit être exécuté en tant que root."
  exit 1
fi

# === INSTALLATION DE SAMBA ===
dnf install -y samba samba-common samba-client

# === CRÉATION DES DOSSIERS PARTAGÉS ===

# Dossier commun
mkdir -p /srv/partage
chmod 0777 /srv/partage
chown nobody:nobody /srv/partage

# Dossier de sauvegardes
mkdir -p /backup
chmod 770 /backup
groupadd -f sambashare
chown root:sambashare /backup

# === SAUVEGARDE smb.conf SI NON DÉJÀ FAITE ===
[ ! -f /etc/samba/smb.conf.bak ] && cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

# === CONFIGURATION DU smb.conf ===
cat <<EOF > /etc/samba/smb.conf
[global]
   workgroup = SAMBA
   server string = Samba Server
   netbios name = samba
   security = user
   map to guest = Bad User
   dns proxy = no

[partage]
   path = /srv/partage
   browsable = yes
   writable = yes
   guest ok = yes
   force user = nobody
   create mask = 0777
   directory mask = 0777

[sauvegardes]
   path = /srv/backup
   browsable = yes
   writable = yes
   valid users = @sambashare
   create mask = 0660
   directory mask = 0770
EOF

# === ACTIVATION DU SERVICE SAMBA ===
systemctl enable --now smb nmb

# === FIREWALL ===
firewall-cmd --permanent --add-service=samba
firewall-cmd --reload

echo "✅ Partages Samba configurés : [partage] (public) et [sauvegardes] (protégé)"