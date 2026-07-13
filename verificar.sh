#!/bin/bash
echo "=========================================="
echo "   DIAGNÓSTICO DEL PORTAL CAUTIVO"
echo "=========================================="

echo -e "\n--- 1. Enrutamiento IP ---"
cat /proc/sys/net/ipv4/ip_forward

echo -e "\n--- 2. Interfaces y direcciones IP ---"
ip -4 addr show

echo -e "\n--- 3. Reglas NAT (MASQUERADE) ---"
iptables -t nat -L POSTROUTING -n -v

echo -e "\n--- 4. Reglas FORWARD (firewall) ---"
iptables -L FORWARD -n -v --line-numbers

echo -e "\n--- 5. Permisos sudo de www-data ---"
ls -l /etc/sudoers.d/99_www_data_iptables 2>/dev/null
cat /etc/sudoers.d/99_www_data_iptables 2>/dev/null

echo -e "\n--- 6. Prueba de ejecución de iptables por www-data ---"
sudo -u www-data sudo /usr/local/bin/portero.sh 192.168.50.99 2>&1

echo -e "\n--- 7. Estado de Apache ---"
systemctl is-active apache2

echo -e "\n--- 8. Últimos errores de Apache ---"
tail -n 10 /var/log/apache2/error.log

echo "=========================================="
echo "   DIAGNÓSTICO COMPLETADO"
echo "=========================================="
