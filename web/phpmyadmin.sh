#!/bin/bash
set -euo pipefail
# 0. Ignorer les Broken pipe
trap '' PIPE

echo -e "\nConfiguration de phpMyAdmin"
echo -e "---------------------------\n"

# 1. Installer PHP et dépendances si non présentes
dnf install -y php php-mysqlnd php-mbstring php-json unzip wget

# 2. Télécharger phpMyAdmin depuis le site officiel (version stable)
VERSION="5.2.1"
cd /usr/share
wget -q "https://files.phpmyadmin.net/phpMyAdmin/${VERSION}/phpMyAdmin-${VERSION}-all-languages.zip" -O phpmyadmin.zip
unzip -q phpmyadmin.zip

if [ ! -d "phpmyadmin" ]; then
    mkdir -p phpmyadmin
    mv "phpMyAdmin-${VERSION}-all-languages" phpmyadmin/
    echo "Déplacement effectué vers phpmyadmin/"
else
    echo "Le dossier phpmyadmin existe déjà, déplacement ignoré."
fi
rm -f phpmyadmin.zip

# 3. Config temporaire
mkdir -p /var/lib/phpmyadmin/tmp
chown -R apache:apache /var/lib/phpmyadmin

# 4. Préparer le fichier de configuration
cd /usr/share/phpmyadmin
cp -n config.sample.inc.php config.inc.php

# Ajouter un blowfish secret uniquement s'il n'existe pas
if ! grep -q "^\\\$cfg\\['blowfish_secret'\\]" config.inc.php; then
    SECRET=$(openssl rand -base64 32)
    sed -i "s|\\\$cfg\\['blowfish_secret'\\] = ''|\\\$cfg['blowfish_secret'] = '$SECRET'|" config.inc.php
    echo "Blowfish secret généré."
else
    echo "Blowfish secret déjà présent, inchangé."
fi

# Définir le répertoire tmp si absent
if ! grep -q "^\\\$cfg\\['TempDir'\\]" config.inc.php; then
    echo "\$cfg['TempDir'] = '/var/lib/phpmyadmin/tmp';" >> config.inc.php
    echo "TempDir défini."
else
    echo "TempDir déjà défini, inchangé."
fi

# 5. Créer un lien dans /srv/web
if [ ! -L /srv/web/phpmyadmin ] && [ ! -e /srv/web/phpmyadmin ]; then
    ln -s /usr/share/phpmyadmin /srv/web/phpmyadmin
    echo "Lien symbolique créé : /srv/web/phpmyadmin -> /usr/share/phpmyadmin"
else
    echo "Le lien ou dossier /srv/web/phpmyadmin existe déjà, création ignorée."
fi

# 6. Apache : créer une conf propre
cat << 'EOF' > /etc/httpd/conf.d/phpmyadmin.conf
Alias /phpmyadmin /usr/share/phpmyadmin

<Directory /usr/share/phpmyadmin>
    AddDefaultCharset UTF-8
    <IfModule mod_authz_core.c>
        Require all granted
    </IfModule>
</Directory>
EOF

# 7. Ajustement SELinux via chcon (non persistant après un relabel complet)
if selinuxenabled; then
    echo "Application de chcon pour permettre l’écriture dans tmp…"
    chcon -R -t httpd_sys_rw_content_t /var/lib/phpmyadmin/tmp
    echo "Contexte temporaire appliqué avec chcon."
fi

# 8. Redémarrage de httpd
echo -e "\nRedémarrage du serveur web..."
systemctl restart httpd

# 9. Vérification finale
echo -e "\nphpMyAdmin installé avec succès !"
echo -e "Accessible à : https://${SERVERNAME:-$(hostname)}.${DOMAIN:-localhost}/phpmyadmin"