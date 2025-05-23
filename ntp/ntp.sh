#!/bin/bash
set -euo pipefail
echo -e "\nConfiguration de CHRONY"
echo -e "-----------------------\n"

# Chargement sécurisé du fichier de configuration
CONFIG_PATH="/etc/Scripts/config.cfg"

if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "Fichier de configuration introuvable : $CONFIG_PATH"
    exit 1
fi

source "$CONFIG_PATH"

# Définir le fuseau horaire
timedatectl set-timezone Europe/Brussels

# Démarrer et activer chronyd
systemctl enable --now chronyd

# Sauvegarde de l'ancien fichier chrony.conf
cp /etc/chrony.conf /etc/chrony.conf.bak

# Ajout des lignes si elles n'existent pas déjà
add_if_missing() {
    local line="$1"
    local file="$2"
    grep -qF -- "$line" "$file" || echo "$line" >> "$file"
}

# Autoriser le sous-réseau AWS
add_if_missing "allow $ADDRESS/$MASK" /etc/chrony.conf

# Autoriser le client spécifique
add_if_missing "allow $IPCLIENT" /etc/chrony.conf

# Définir ce serveur comme source NTP (utile si ce script est lancé sur un autre client aussi)
add_if_missing "server $IPADD iburst" /etc/chrony.conf

# Ajout des serveurs de temps publics BE
for srv in 0.be.pool.ntp.org 1.be.pool.ntp.org 2.be.pool.ntp.org 3.be.pool.ntp.org; do
    add_if_missing "server $srv iburst" /etc/chrony.conf
done

# Redémarrer le service
systemctl restart chronyd

# Activer la synchronisation NTP via systemd
timedatectl set-ntp true

echo -e "\n Configuration de CHRONY terminée avec succès"
echo -e "----------------------------------------------\n"