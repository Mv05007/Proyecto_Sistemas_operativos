#!/bin/bash

echo "=========================================="
echo " REPORTE DE DIAGNÓSTICO DEL SISTEMA "
echo "=========================================="

echo -e "\n--- 1. ESTADO DE IP FORWARDING (ENRUTAMIENTO) ---"
cat /proc/sys/net/ipv4/ip_forward

echo -e "\n--- 2. INTERFACES Y DIRECCIONES IP ---"
ip -4 addr show

echo -e "\n--- 3. REGLAS DE NAT (MASQUERADE) ---"
iptables -t nat -L POSTROUTING -n -v

echo -e "\n--- 4. REGLAS DEL FIREWALL (CADENA FORWARD) ---"
iptables -L FORWARD -n -v --line-numbers

echo -e "\n--- 5. PERMISOS DE APACHE EN SUDOERS ---"
ls -l /etc/sudoers.d/99_www_data_iptables 2>/dev/null
cat /etc/sudoers.d/99_www_data_iptables 2>/dev/null

echo -e "\n--- 6. PRUEBA DE PRIVILEGIOS DE APACHE ---"
# Simulamos ser la página web ejecutando el comando del firewall
su -s /bin/bash www-data -c "sudo /usr/sbin/iptables -L FORWARD -n" 2>&1

echo -e "\n--- 7. ESTADO DE SERVICIOS (Apache / DNS) ---"
systemctl is-active apache2 dnsmasq

echo -e "\n--- 8. ÚLTIMOS ERRORES DE APACHE ---"
tail -n 10 /var/log/apache2/error.log

echo -e "\n=========================================="
echo " DIAGNÓSTICO COMPLETADO "
echo "=========================================="
