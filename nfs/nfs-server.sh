#!/bin/bash

# Répertoire à partager
EXPORT_DIR="/mnt/shared"
# IP réseau du client
CLIENT_NET="" 

echo "[*] Configuration de NFS avec partage: $EXPORT_DIR"

# Installer les paquets
dnf check-update 
dnf install -y nfs-utils
systemctl start nfs-server
systemctl start nfs-mountd
systemctl start rpcbind
echo "[+] Activation des services nfs-server, rpcbind et nfs-mountd"

# Ouverture des ports
firewall-cmd --permanent --add-service=nfs
firewall-cmd --permanent --add-service=mountd
firewall-cmd --permanent --add-service=rpc-bind
echo "[+] Ajout des services dans le firewall"

firewall-cmd --reload
echo "[*] Relancement des services permanents du firewall."

# Créer le dossier exporté
mkdir -p $EXPORT_DIR
chown nobody:nobody $EXPORT_DIR
chmod 777 $EXPORT_DIR

# Ajouter à /etc/exports
echo "$EXPORT_DIR $CLIENT_NET(rw,sync,no_subtree_check)" >> /etc/exports

# Exporter et redémarrer
exportfs -ra
echo "[+] Ajout des exports dans la liste."
systemctl restart nfs-server
echo "[*] Redémarrage du service nfs-server."

echo "[+] NFS configuré pour le réseau $CLIENT_NET."
