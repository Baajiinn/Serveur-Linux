#!/bin/bash
set -euo pipefail
echo -e "\n[1/3] Vérification de l'installation de Netdata..."

HEALTH_DIR="/opt/netdata/etc/netdata/health.d"

if [ ! -d "$HEALTH_DIR" ]; then
  echo "Erreur : le dossier $HEALTH_DIR est introuvable. Vérifie que Netdata (version statique) est bien installé."
  exit 1
fi

echo -e "\n[2/3] Création des alertes de surveillance pour les services..."

# Liste des services à surveiller
SERVICES=("named" "vsftpd" "nfs-server" "httpd" "mariadb" "smb" "chronyd" "sshd")

for SERVICE in "${SERVICES[@]}"; do
  CONF_FILE="$HEALTH_DIR/${SERVICE}.conf"

  echo "Création de l'alerte pour : $SERVICE"
  cat <<EOF | sudo tee "$CONF_FILE" > /dev/null
# Fichier généré automatiquement - Surveillance du service $SERVICE

template: service_status_${SERVICE}
      on: systemd_services.${SERVICE}
   class: System
    type: Service
component: ${SERVICE}
     os: linux

alarm: ${SERVICE}_down
   every: 10s
     warn: \$status != "running"
     info: "Le service ${SERVICE} est arrêté."
      to: sysadmin
EOF

done

echo -e "\n[3/3] Redémarrage de Netdata..."
sudo systemctl restart netdata

echo -e "\nConfiguration terminée. Accède à ton interface Netdata : http://<TON-IP>:19999 → Health → Alarms"