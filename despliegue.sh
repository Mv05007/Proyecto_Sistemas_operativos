#!/bin/bash
echo "=== Instalando Portal Cautivo ==="

# 1. Copiar la web a Apache
cp indexx.php /var/www/html/indexx.php
chown www-data:www-data /var/www/html/indexx.php
chmod 644 /var/www/html/indexx.php

# 2. Configurar permisos de sistema
echo "www-data ALL=(ALL) NOPASSWD: /usr/sbin/iptables" > /etc/sudoers.d/99_www_data_iptables
chmod 440 /etc/sudoers.d/99_www_data_iptables

# 3. Poner el candado del Firewall
iptables -F FORWARD
iptables -A FORWARD -s 192.168.50.0/24 -j DROP

# 4. Reiniciar Apache
systemctl restart apache2

echo "¡Despliegue finalizado exitosamente!"
