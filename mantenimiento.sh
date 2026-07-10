#!/bin/bash

echo "=== HERRAMIENTAS DE MANTENIMIENTO ==="
echo "1. Ver estado de servicios"
echo "2. Ver clientes conectados"
echo "3. Ver reglas iptables"
echo "4. Desbloquear IP específica"
echo "5. Bloquear IP específica"
echo "6. Ver logs DNS"
echo "7. Reiniciar servicios"
echo "8. Salir"

read -p "Selecciona una opción: " opcion

case $opcion in
    1)
        sudo systemctl status dnsmasq apache2 --no-pager
        ;;
    2)
        echo " Clientes conectados:"
        cat /var/lib/dnsmasq/dnsmasq.leases
        ;;
    3)
        sudo iptables -L -n -v | head -30
        ;;
    4)
        read -p "IP a desbloquear: " ip
        sudo iptables -I FORWARD -s $ip -j ACCEPT
        echo " IP $ip desbloqueada"
        ;;
    5)
        read -p "IP a bloquear: " ip
        sudo iptables -D FORWARD -s $ip -j ACCEPT 2>/dev/null
        echo " IP $ip bloqueada"
        ;;
    6)
        sudo tail -30 /var/log/dnsmasq.log
        ;;
    7)
        sudo systemctl restart dnsmasq apache2
        echo " Servicios reiniciados"
        ;;
    8)
        exit 0
        ;;
    *)
        echo " Opción inválida"
        ;;
esac
