#!/bin/bash

# Vérifie si l'utilisateur est root
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en tant que root."
    exit 1
fi

# === INSTALLATION ===
sudo dnf install httpd -y

# === CONFIGURATION ===
base_domain=cloud.local
zone_directe=/var/named/cloud.local.forward
zone_inverse=/var/named/cloud.local.reversed

# Afficher les variables pour vérification
echo "Base domain : $base_domain"
echo "Zone directe : $zone_directe"
echo "Zone inverse : $zone_inverse"

# === SAISIE UTILISATEUR ===
user=$1
password=$2
ip=$(hostname -I | awk '{print $1}')

# === CONSTRUCTION DU NOM DE DOMAINE ===
domain="${user}.${base_domain}"
ip_last_octet=$(echo "$ip" | awk -F. '{print $4}')

# === CRÉATION DU DOSSIER WEB ===
mkdir -p /var/www/$domain/public_html

cat > /var/www/$domain/public_html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Bienvenue sur $domain</title>
</head>
<body>
    <h1>Site de $domain opérationnel !</h1>
</body>
</html>
EOF

# === CONFIGURATION DU VIRTUALHOST APACHE ===
conf_file="/etc/httpd/conf.d/$domain.conf"

cat > "$conf_file" <<EOF
<VirtualHost *:80>
    ServerName $domain
    ServerAlias www.$domain
    DocumentRoot /var/www/$domain/public_html
    <Directory /var/www/$domain/public_html>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog /var/log/httpd/$domain-error.log
    CustomLog /var/log/httpd/$domain-access.log combined
</VirtualHost>
EOF

chown -R apache:apache /var/www/$domain/public_html
chmod -R 755 /var/www/$domain

# === AJOUT DANS LA ZONE DIRECTE ===
echo -e "\n; Ajout automatique pour $domain\n$user    IN      A       $ip" >> "$zone_directe"

# === AJOUT DANS LA ZONE INVERSE ===
echo -e "\n; Ajout automatique pour $ip ($domain)\n$ip_last_octet    IN      PTR     $domain." >> "$zone_inverse"

# === INCRÉMENTATION DU SERIAL ===
increment_serial() {
    zone_file="$1"
    current_serial=$(grep -E '^[ \t]*[0-9]{10}[ \t]*;[ \t]*Serial' "$zone_file" | awk '{print $1}')
    if [ -z "$current_serial" ]; then
        echo "Serial introuvable dans $zone_file, skipping..."
        return
    fi
    new_serial=$((current_serial + 1))
    sed -i "s/$current_serial[ \t]*;[ \t]*Serial/$new_serial ; Serial/" "$zone_file"
}

increment_serial "$zone_directe"
increment_serial "$zone_inverse"

# === RECHARGEMENT DE BIND ET HTTPD ===
echo "Rechargement de BIND et Apache..."
rndc reload
systemctl restart httpd

echo "Le site $domain est prêt avec l'IP $ip. DNS et Apache sont configurés."

smbpasswd -e "$user"

# === CONFIGURATION SAMBA ===


# Vérifier que Samba est installé
dnf install samba samba-common -y

# Ajouter l'utilisateur système s'il n'existe pas
if ! id "$user" &>/dev/null; then
    useradd "$user"
    echo "Utilisateur système $user créé."
fi

# Ajouter ou mettre à jour l'utilisateur Samba
(echo $password ; echo $password ) | smbpasswd -s -a "$user"

# Créer une section Samba dans smb.conf s'il n'existe pas déjà
share_path="/var/www/$domain/"
smb_section="\n[$domain]
   path = $share_path
   valid users = $user
   browsable = yes
   writable = yes
   read only = no
   create mask = 0644
   directory mask = 0755
"

# Ajouter la section uniquement si elle n'existe pas
if ! grep -q "^\[$domain\]" /etc/samba/smb.conf; then
    echo -e "$smb_section" >> /etc/samba/smb.conf
    echo "Partage Samba [$domain] ajouté."
else
    echo "Partage Samba [$domain] déjà existant dans smb.conf."
fi

# Définir les bons droits
chown -R "$user":"$user" "$share_path"

# Activer et redémarrer Samba
systemctl enable smb nmb
systemctl restart smb nmb


echo "Partage Samba [$domain] configuré pour l'utilisateur $user sur $share_path."