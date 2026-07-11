#!/bin/bash

echo "Iniciando configuración completa del Portal Cautivo..."

# --- 1. ENRUTAMIENTO Y NAT ---
# Habilitar el reenvío de paquetes (Vital para que el servidor actúe como router)
sudo sysctl -w net.ipv4.ip_forward=1

# Limpieza total de reglas de firewall anteriores
sudo iptables -F
sudo iptables -t nat -F

# Configurar NAT para enmascarar el tráfico de salida de los clientes
sudo iptables -t nat -A POSTROUTING -j MASQUERADE

# --- 2. CONFIGURACIÓN DE RED (El Candado) ---
# Aplicar el bloqueo por defecto a la red de clientes (Modificar si tu red es distinta)
sudo iptables -A FORWARD -s 192.168.50.0/24 -j DROP

# --- 3. CONFIGURACIÓN DE PERMISOS SUDO ---
# Asegurar que el usuario web pueda ejecutar iptables sin contraseña para dar acceso
echo "www-data ALL=(ALL) NOPASSWD: /usr/sbin/iptables" | sudo tee /etc/sudoers.d/portal-cautivo
sudo chmod 440 /etc/sudoers.d/portal-cautivo

# --- 4. PREPARACIÓN DEL PORTAL WEB ---
# Asegurar que el archivo PHP tenga los permisos correctos para Apache
sudo chown www-data:www-data /var/www/html/indexx.php
sudo chmod 644 /var/www/html/indexx.php

echo "=========================================================="
echo "DESPLIEGUE COMPLETADO CON ÉXITO!"
echo "El servidor está enrutando y listo para interceptar."
echo "La política de DROP está aplicada a 192.168.50.0/24"
echo "=========================================================="
