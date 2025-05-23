#!/bin/bash
set -euo pipefail

# Variables 
SERVER_IP="192.168.0.186"
REMOTE_DIR="/opt/remote_storage/"

# Création du répertoire
mkdir -p $REMOTE_DIR

# Installation du client NFS
dnf install -y nfs-utils 

# Montage du répertoire NFS
time mount -t nfs $SERVER_IP:/mnt/shared $REMOTE_DIR
mount -t nfs $SERVER_IP:/mnt/shared $REMOTE_DIR

# Vérification du montage
if mountpoint -q "$REMOTE_DIR"; then
    echo "[+] Montage réussi de NFS sur $REMOTE_DIR"
    touch "$REMOTE_DIR/test_file"
    if [ -f "$REMOTE_DIR/test_file" ]; then
        echo "[+] Test de fichier réussi dans $REMOTE_DIR"
    else 
        echo "[-] Échec du test de fichier dans $REMOTE_DIR"
    fi
else
    echo "[-] Échec du montage de NFS sur $REMOTE_DIR"
fi

# Ajout au fstab pour montage automatique
echo "$SERVER_IP:/mnt/shared/ $REMOTE_DIR nfs defaults 0 0" >> /etc/fstab
echo "[+] Ajouté à /etc/fstab pour montage automatique"
echo "[*] Configuration NFS client terminée."
