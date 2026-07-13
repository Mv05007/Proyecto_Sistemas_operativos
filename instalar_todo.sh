#!/bin/bash
echo "=== INSTALACIÓN COMPLETA DEL PORTAL CAUTIVO ==="

# 1. Configurar red y enrutamiento
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ipforward.conf
sysctl -p /etc/sysctl.d/99-ipforward.conf

# 2. Limpiar iptables
iptables -F
iptables -t nat -F
iptables -X
iptables -t nat -X

# 3. NAT para dar salida a Internet
iptables -t nat -A POSTROUTING -o ens33 -j MASQUERADE

# 4. Regla general: todo el tráfico FORWARD a la subred se bloquea (candado)
iptables -A FORWARD -s 192.168.50.0/24 -j DROP

# 5. Aplicar bloqueos de dominios (Instagram y ChatGPT) - SE EJECUTA ANTES DE CUALQUIER ACCEPT
bash bloqueo_redes.sh

# 6. Configurar dnsmasq
cp dnsmasq.conf /etc/dnsmasq.conf
systemctl restart dnsmasq
systemctl enable dnsmasq

# 7. Copiar la página web al servidor Apache
cp indexx.php /var/www/html/indexx.php
chown www-data:www-data /var/www/html/indexx.php
chmod 644 /var/www/html/indexx.php

# 8. Dar permisos a Apache para ejecutar iptables (sin contraseña)
echo "www-data ALL=(ALL) NOPASSWD: /sbin/iptables" > /etc/sudoers.d/99_www_data_iptables
chmod 440 /etc/sudoers.d/99_www_data_iptables

# 9. Reiniciar Apache
systemctl restart apache2

echo "=== INSTALACIÓN COMPLETA ==="
echo "Ve al cliente y abre http://192.168.50.1/indexx.php"
echo "Usuario: estudiante   Contraseña: 123456"
