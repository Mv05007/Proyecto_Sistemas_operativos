#!/bin/bash
echo "=== INSTALACIÓN DEL PORTAL CAUTIVO FINAL ==="

# 1. Activar enrutamiento
sysctl -w net.ipv4.ip_forward=1

# 2. Limpiar reglas anteriores
iptables -F
iptables -t nat -F
iptables -t nat -X

# 3. Reglas de bloqueo de dominios (se aplican a TODO el tráfico, incluso autenticado)
# Nota: asumimos que la interfaz interna es ens33. Si es otra (eth0, enp0s3), cámbiala abajo.
iptables -A FORWARD -m string --string "instagram.com" --algo bm --to 65535 -j REJECT
iptables -A FORWARD -m string --string "chatgpt.com" --algo bm --to 65535 -j REJECT
iptables -A FORWARD -m string --string "openai.com" --algo bm --to 65535 -j REJECT

# 4. Regla de denegación general para toda la subred (los no autenticados)
iptables -A FORWARD -s 192.168.50.0/24 -j DROP

# 5. Redirección de puerto 80 (HTTP) hacia el portal (para forzar el login)
# Cambia "ens33" por tu interfaz interna si es diferente (ej. eth0, enp0s3)
iptables -t nat -A PREROUTING -i ens33 -p tcp --dport 80 -j DNAT --to-destination 192.168.50.1:80
iptables -t nat -A POSTROUTING -j MASQUERADE

# 6. Instalar el script portero
chmod +x portero.sh
cp portero.sh /usr/local/bin/portero.sh

# 7. Configurar sudoers para que Apache (www-data) pueda ejecutar el portero sin contraseña
echo -e "Defaults:www-data !requiretty\nwww-data ALL=(ALL) NOPASSWD: /usr/local/bin/portero.sh" > /etc/sudoers.d/99_www_data_iptables
chmod 440 /etc/sudoers.d/99_www_data_iptables

# 8. Copiar la página web
cp indexx.php /var/www/html/indexx.php
chown www-data:www-data /var/www/html/indexx.php
chmod 644 /var/www/html/indexx.php

# 9. Reiniciar Apache
systemctl restart apache2

echo "=== ¡INSTALACIÓN COMPLETA! ==="
echo "Ahora ve al cliente y abre http://192.168.50.1/indexx.php"
