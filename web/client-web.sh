#!/bin/bash
set -euo pipefail
echo -e "\nConfiguration de HTTPD"
echo -e "----------------------\n"

# 0. Installation (si pas déjà installés)
sudo dnf install -y httpd mod_ssl openssl policycoreutils-python-utils

# 1. Chargement des variables de config
source /etc/Scripts/config.cfg

# 2. Démarrer et activer Apache
systemctl start httpd
systemctl enable httpd

# 3. Sauvegarde du fichier de configuration original
HTTPD_CONF="/etc/httpd/conf/httpd.conf"
cp $HTTPD_CONF $HTTPD_CONF.bak

# 4. Modification du fichier httpd.conf
sed -i "s|^#ServerName.*|ServerName $SERVERNAME.$DOMAIN:80|" $HTTPD_CONF
sed -i 's|^ *Options Indexes FollowSymLinks|Options FollowSymLinks|' $HTTPD_CONF
sed -i 's|^ *AllowOverride None|AllowOverride All|' $HTTPD_CONF
sed -i 's|^DirectoryIndex .*|DirectoryIndex index.html index.php index.cgi|' $HTTPD_CONF

# Ajouter directives à la fin
echo "# server's response header" >> $HTTPD_CONF
echo "ServerTokens Prod" >> $HTTPD_CONF

# 5. Suppression de la page par défaut
rm -f /etc/httpd/conf.d/welcome.conf

# 6. Création des répertoires web
mkdir -p /srv/web /srv/web/$PRIMARYUSER

# 7. Création du certificat SSL auto-signé (si inexistant)
SSL_DIR="/etc/ssl/certs"
CRT="$SSL_DIR/httpd-selfsigned.crt"
KEY="$SSL_DIR/httpd-selfsigned.key"

if [[ ! -f $CRT || ! -f $KEY ]]; then
    echo "Création du certificat SSL auto-signé..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$KEY" \
        -out "$CRT" \
        -subj "/C=FR/ST=Cloud/L=AWS/O=IT/CN=$SERVERNAME.$DOMAIN"
fi

# 8. VirtualHost principal
cat << EOF > /etc/httpd/conf.d/main.conf
<VirtualHost *:80>
    ServerName $SERVERNAME.$DOMAIN
    ServerAlias www.$SERVERNAME.$DOMAIN
    Redirect permanent / https://$SERVERNAME.$DOMAIN/
</VirtualHost>

<VirtualHost _default_:443>
    ServerName $SERVERNAME.$DOMAIN
    DocumentRoot /srv/web/
    SSLEngine on
    SSLCertificateFile $CRT
    SSLCertificateKeyFile $KEY
</VirtualHost>

<Directory "/srv/web">
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF

# 9. Page principale
cat << 'EOF' > /srv/web/index.html
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Page principale</title></head>
<body><h1>Bienvenue sur la page principale</h1></body>
</html>
EOF

# 10. VirtualHost utilisateur principal
cat << EOF > /etc/httpd/conf.d/$PRIMARYUSER.conf
<VirtualHost *:80>
    ServerName $PRIMARYUSER.$SERVERNAME.$DOMAIN
    Redirect permanent / https://$PRIMARYUSER.$SERVERNAME.$DOMAIN/
</VirtualHost>

<VirtualHost _default_:443>
    ServerName $PRIMARYUSER.$SERVERNAME.$DOMAIN
    DocumentRoot /srv/web/$PRIMARYUSER
    SSLEngine on
    SSLCertificateFile $CRT
    SSLCertificateKeyFile $KEY
</VirtualHost>

<Directory "/srv/web/$PRIMARYUSER">
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF

# 11. Page utilisateur principal
cat << EOF > /srv/web/$PRIMARYUSER/index.php
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>$PRIMARYUSER Page</title></head>
<body><h1>Bienvenue sur la page de $PRIMARYUSER</h1></body>
</html>
EOF

# 12. SELinux : autoriser Apache à accéder à /srv/web
semanage fcontext -a -e /var/www /srv/web 2>/dev/null || echo "Contexte déjà appliqué"
restorecon -Rv /srv/web

# 13. Vérification de la configuration Apache
if apachectl configtest; then
    echo -e "\nSyntaxe OK, redémarrage de httpd..."
    systemctl restart httpd
    echo -e "\nHTTPD a été configuré avec succès !"
else
    echo -e "\nErreur dans la configuration Apache. Vérifiez les fichiers .conf"
fi