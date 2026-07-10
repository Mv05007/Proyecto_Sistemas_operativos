#!/bin/bash

echo "=== DIAGNÓSTICO DEL SISTEMA ==="
echo ""

echo "📡 Interfaces de red:"
ip -o link show | awk -F': ' '{print "  - " $2}' | grep -v lo
echo ""

echo "IPs asignadas:"
ip -4 addr show | grep -E "^[0-9]+:|inet " | grep -v "127.0.0.1"
echo ""

echo "🔌 Conectividad a Internet:"
ping -c 2 8.8.8.8 &> /dev/null && echo "   Internet funcionando" || echo "   Sin Internet"
echo ""

echo " Servicios instalados:"
for service in dnsmasq apache2; do
    if systemctl is-active --quiet $service; then
        echo "  $service activo"
    else
        echo "   $service inactivo"
    fi
done
echo ""

echo " Clientes DHCP:"
if [ -f /var/lib/dnsmasq/dnsmasq.leases ]; then
    cat /var/lib/dnsmasq/dnsmasq.leases | while read line; do
        echo "  - $line"
    done
else
    echo "  No hay clientes conectados"
fi
echo ""

echo " Reglas iptables (primeras 10):"
sudo iptables -L -n -v | head -10
echo ""

echo " Diagnóstico completado"
