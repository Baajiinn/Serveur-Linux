#!/bin/bash
set -euo pipefail
# Chargement de la config
CONFIG_FILE="/etc/Scripts/config.cfg"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Erreur : le fichier $CONFIG_FILE est introuvable."
  exit 1
fi

source "$CONFIG_FILE"

if [ -z "$IPADD" ] || [ -z "$DOMAIN" ] || [ -z "$SERVERNAME" ]; then
  echo "Erreur : les variables IPADD, DOMAIN ou SERVERNAME ne sont pas définies dans $CONFIG_FILE."
  exit 1
fi

FQDN="$SERVERNAME.$DOMAIN"

echo -e "\n--- Test de résolution DNS ---\n"

# Test dig - Résolution directe
echo "Test dig (résolution A) pour $FQDN :"
dig @"$IPADD" "$FQDN" +short
echo

# Test dig - Résolution inversée
echo "Test dig (résolution PTR) pour $IPADD :"
dig @"$IPADD" -x "$IPADD" +short
echo

# Test nslookup - Résolution directe
echo "Test nslookup (A) :"
nslookup "$FQDN" "$IPADD"
echo

# Test nslookup - Résolution inversée
echo "Test nslookup (PTR) :"
nslookup "$IPADD" "$IPADD"
echo

echo "--- Fin du test DNS ---"