#!/bin/bash

echo -e "\n--- Configuration du pare-feu avec iptables (AWS Ready) ---\n"

# 1. (Optionnel) Supprimer firewalld si installé
if systemctl is-active --quiet firewalld; then
    echo "Désactivation de firewalld..."
    systemctl disable --now firewalld
    dnf -y remove firewalld
fi

# Installer iptables si nécessaire
if ! command -v iptables &> /dev/null; then
    echo "Installation de iptables..."
    sudo dnf install -y iptables iptables-services
fi

# 2. Réinitialiser les règles
iptables -F
iptables -X

# 3. Politique par défaut : bloquer tout
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# 4. Autoriser les connexions sur loopback (localhost)
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# 5. Autoriser connexions établies
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 6. Autoriser SSH
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A OUTPUT -p tcp --sport 22 -j ACCEPT

# 7. ICMP (Ping)
iptables -A INPUT -p icmp -j ACCEPT
iptables -A OUTPUT -p icmp -j ACCEPT

# 8. HTTP / HTTPS
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

# 9. DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -j ACCEPT

# 10. NTP (chronyd)
iptables -A OUTPUT -p udp --dport 123 -j ACCEPT
iptables -A INPUT -p udp --sport 123 -j ACCEPT

# 11. MariaDB
iptables -A INPUT -p tcp --dport 3306 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 3306 -j ACCEPT

# 12. FTP (attention à mode passif)
iptables -A INPUT -p tcp --dport 21 -j ACCEPT
iptables -A INPUT -p tcp --dport 20 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 21 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 20 -j ACCEPT

# FTP standard
#iptables -A INPUT -p tcp --dport 21 -j ACCEPT
#iptables -A OUTPUT -p tcp --sport 21 -j ACCEPT

# Mode passif FTP (vsftpd)
#iptables -A INPUT -p tcp --dport 60000:61000 -j ACCEPT
#iptables -A OUTPUT -p tcp --sport 60000:61000 -j ACCEPT

# 13. ClamAV
iptables -A INPUT -p tcp --dport 3310 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 3310 -j ACCEPT

# 14. Messagerie
for port in 25 110 143 587; do
    iptables -A INPUT -p tcp --dport $port -j ACCEPT
    iptables -A OUTPUT -p tcp --dport $port -j ACCEPT
done

echo -e "\n--- iptables configuré avec succès ---\n"