#!/bin/bash
set -euo pipefail
echo -e "\n--- Configuration du serveur DNS (named) ---\n"

# Chemin vers le fichier de configuration
CONFIG_FILE="/etc/Scripts/config.cfg"
source $CONFIG_FILE
# Vérification de l'existence du fichier config
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Erreur : le fichier $CONFIG_FILE est introuvable."
  exit 1
fi

# Chargement des variables
source "$CONFIG_FILE"

# Vérification des variables essentielles
if [ -z "$IPADD" ] || [ -z "$DOMAIN" ] || [ -z "$SERVERNAME" ]; then
  echo "Erreur : les variables IPADD, DOMAIN ou SERVERNAME ne sont pas définies dans $CONFIG_FILE."
  exit 1
fi

# Installation des paquets nécessaires
dnf install -y bind bind-utils policycoreutils-python-utils cronie

# Activation des services
systemctl enable named
systemctl enable crond
systemctl start crond

# Création des fichiers de zone
FORWARD_FILE="/var/named/${DOMAIN}.forward"
REVERSE_FILE="/var/named/${DOMAIN}.reversed"
ZONE_NAME="$DOMAIN"
REVERSE_ZONE="0.42.10.in-addr.arpa"

cat > "$FORWARD_FILE" <<EOF
\$TTL 86400
@   IN  SOA $SERVERNAME.$DOMAIN. root.$DOMAIN. (
        2023051201  ; Serial
        3600        ; Refresh
        1800        ; Retry
        604800      ; Expire
        86400       ; Minimum TTL
)
    IN  NS  $SERVERNAME.$DOMAIN.
$SERVERNAME IN A $IPADD
EOF

cat > "$REVERSE_FILE" <<EOF
\$TTL 86400
@   IN  SOA $SERVERNAME.$DOMAIN. root.$DOMAIN. (
        2023051201
        3600
        1800
        604800
        86400
)
    IN  NS  $SERVERNAME.$DOMAIN.
$(echo $IPADD | awk -F. '{print $4}') IN PTR $SERVERNAME.$DOMAIN.
EOF

# Changement des permissions et contexte SELinux
chown root:named "$FORWARD_FILE" "$REVERSE_FILE"
chmod 640 "$FORWARD_FILE" "$REVERSE_FILE"
restorecon -v "$FORWARD_FILE" "$REVERSE_FILE"

# Modification de named.conf
NAMED_CONF="/etc/named.conf"

# Sauvegarde
cp "$NAMED_CONF" "${NAMED_CONF}.bak"

# 1. Vérifier que l'IP est présente dans le bloc 'options'
if ! grep -qE "^\s*listen-on\s+port\s+53\s+\{\s*.*${IPADD}.*\};" "$NAMED_CONF"; then
    echo "[+] Ajout de l'IP $IPADD dans le bloc options de $NAMED_CONF"
    # On insère la directive listen-on juste avant la fin du bloc options
    sed -i "/^options\s*{/a\    listen-on port 53 { ${IPADD}; };\n" "$NAMED_CONF"
else
    echo "[=] L'IP $IPADD est déjà configurée dans le bloc options."
fi

# Ajout de la configuration si absente
if ! grep -q "$ZONE_NAME" "$NAMED_CONF"; then
cat >> "$NAMED_CONF" <<EOF

zone "$ZONE_NAME" IN {
    type master;
    file "$FORWARD_FILE";
    allow-update { none; };
};

zone "$REVERSE_ZONE" IN {
    type master;
    file "$REVERSE_FILE";
    allow-update { none; };
};
EOF
fi

# Suppression de l'option obsolète
sed -i '/dnssec-enable/d' "$NAMED_CONF"

# Vérification de la config
named-checkconf
named-checkzone "$ZONE_NAME" "$FORWARD_FILE"
named-checkzone "$REVERSE_ZONE" "$REVERSE_FILE"

# Redémarrage du service
systemctl restart named

# Vérification du statut
systemctl status named --no-pager

echo -e "\n--- Configuration de NAMED terminée sur $IPADD ($SERVERNAME.$DOMAIN) ---"