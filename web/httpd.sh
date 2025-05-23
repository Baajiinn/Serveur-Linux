#!/bin/bash
set -euo pipefail

# Variables (à adapter si besoin)
HTTP_PORT=80
HTTPS_PORT=443
IPTABLES_CONF=/etc/sysconfig/iptables

# Installations
sudo dnf install -y httpd lynx

# Activation du service HTTPD
sudo systemctl start httpd
sudo systemctl enable httpd
sudo systemctl status httpd
sudo systemctl restart httpd

# --- Configuration du pare‑feu avec iptables ---
echo "[+] Configuration du pare‑feu avec iptables"

# 1. Autoriser les requêtes DNS sortantes (UDP & TCP)
sudo iptables -A OUTPUT -p udp --dport 53   -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53   -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT  -p udp --sport 53   -m conntrack --ctstate ESTABLISHED         -j ACCEPT
sudo iptables -A INPUT  -p tcp --sport 53   -m conntrack --ctstate ESTABLISHED         -j ACCEPT

# 2. Autoriser HTTP et HTTPS sortants (navigation)
sudo iptables -A OUTPUT -p tcp --dport ${HTTP_PORT}  -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport ${HTTPS_PORT} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT

# 3. Autoriser HTTP et HTTPS entrants (hébergement web)
sudo iptables -A INPUT  -p tcp --dport ${HTTP_PORT}  -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT  -p tcp --dport ${HTTPS_PORT} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -A OUTPUT -p tcp --sport ${HTTP_PORT}  -m conntrack --ctstate ESTABLISHED         -j ACCEPT
sudo iptables -A OUTPUT -p tcp --sport ${HTTPS_PORT} -m conntrack --ctstate ESTABLISHED         -j ACCEPT

# 4. [Optionnel] Bloquer tout le reste (si politique par défaut DROP)
# sudo iptables -P INPUT   DROP
# sudo iptables -P OUTPUT  DROP
# sudo iptables -P FORWARD DROP

# 5. Sauvegarde des règles pour persistance
sudo sh -c "iptables-save > ${IPTABLES_CONF}"
sudo systemctl enable iptables
sudo systemctl restart iptables

echo "[+] Règles iptables appliquées et sauvegardées dans ${IPTABLES_CONF}"

# --- Configuration SELinux pour Apache ---
sudo setsebool -P httpd_can_network_connect      1
sudo setsebool -P httpd_can_network_connect_db   1
sudo setsebool -P httpd_can_network_relay        1

# Fonction utilitaire pour initialiser un site
create_site() {
    site_user="$1"
    site_dir="/var/www/${site_user}"
    html_dir="${site_dir}/html"

    echo "[+] Création et configuration du site ${site_user}"
    sudo mkdir -p "${html_dir}"
    sudo chown -R "${site_user}":"${site_user}" "${site_dir}"
    sudo chmod 755 "${site_dir}"
    sudo find "${html_dir}" -type d -exec chmod 755 {} \;
    sudo find "${html_dir}" -type f -exec chmod 644 {} \;

    # Création automatique des fichiers index.html et index.php
    sudo tee "${html_dir}/index.html" > /dev/null << HTML_EOF
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Bienvenue sur ${site_user}.com</title>
</head>
<body>
    <h1>Site de ${site_user}</h1>
    <p>Ceci est la page d'accueil HTML par défaut.</p>
</body>
</html>
HTML_EOF

    sudo tee "${html_dir}/index.php" > /dev/null << PHP_EOF
<?php
// Page d'accueil PHP par défaut pour ${site_user}
echo "<!DOCTYPE html>";
echo "<html lang='fr'>";
echo "<head><meta charset='UTF-8'><title>PHP - ${site_user}</title></head>";
echo "<body><h1>Bienvenue sur ${site_user}.com via PHP</h1>";
echo "<p>Ceci est la page d'accueil PHP par défaut.</p>";
echo "</body></html>";
?>
PHP_EOF

    # VirtualHost
    sudo tee /etc/httpd/conf.d/${site_user}.conf > /dev/null << VHOST_EOF
<VirtualHost *:80>
    ServerAdmin root@root.com
    DocumentRoot ${html_dir}
    ServerName ${site_user}.com

    <Directory "${html_dir}">
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
        DirectoryIndex index.php index.html
        ErrorDocument 404 /error/404.html
        ErrorDocument 500 /error/500.html
    </Directory>
</VirtualHost>
VHOST_EOF

    sudo chmod 644 /etc/httpd/conf.d/${site_user}.conf
    sudo chown apache:apache /etc/httpd/conf.d/${site_user}.conf
}

# --- Configuration des VirtualHosts statiques ---

# Site root
create_site "root"

# Relance Apache
sudo apachectl restart
sleep 2

# Site ec2-user
create_site "ec2-user"

sudo apachectl restart

# --- Wrapper useradd pour créer automatiquement un VirtualHost --
#    avec refus explicite de création de 'root' et index par défaut
if [[ ! -f /usr/sbin/useradd.real ]]; then
    echo "[+] Création du wrapper useradd"
    sudo mv /usr/sbin/useradd /usr/sbin/useradd.real

    sudo tee /usr/sbin/useradd > /dev/null << 'EOF'
#!/bin/bash
# Wrapper useradd : refuse la création de 'root' et sinon crée l'utilisateur + VirtualHost

user="\$1"

# Refus de la création de l'utilisateur 'root'
if [ "\$user" = "root" ]; then
    echo "Erreur : création de l'utilisateur 'root' interdite par ce wrapper." >&2
    exit 1
fi

# Appel du vrai useradd
/usr/sbin/useradd.real "\$@"
status=\$?
if [ \$status -eq 0 ]; then
    # Utiliser la même fonction de création de site
    bash -c "create_site '\${user}'"
    echo "[+] VirtualHost et pages index créés pour \${user}"
fi

exit \$status
EOF

    sudo chmod 755 /usr/sbin/useradd
fi

echo "[+] Script terminé."