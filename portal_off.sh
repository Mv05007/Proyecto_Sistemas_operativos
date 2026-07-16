#!/bin/bash
# ============================================================
# portal_off.sh - Desactiva el portal cautivo temporalmente
#                 para que los clientes tengan acceso libre a internet
# ============================================================

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

mensaje() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
advertencia() { echo -e "${YELLOW}[WARN]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    error "Ejecuta como root: sudo ./portal_off.sh"
fi

# Detectar interfaces
WAN_IF=$(ip route | grep default | awk '{print $5}' | head -1)
LAN_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -v "$WAN_IF" | head -1)

if [ -z "$WAN_IF" ] || [ -z "$LAN_IF" ]; then
    advertencia "No se pudieron detectar automáticamente. Introduce manualmente:"
    read -p "Interfaz WAN (ej. ens33): " WAN_IF
    read -p "Interfaz LAN (ej. ens34): " LAN_IF
fi

mensaje "WAN: $WAN_IF  |  LAN: $LAN_IF"

# Guardar estado actual de iptables (por si queremos restaurar después)
mkdir -p /root/portal_backup
iptables-save > /root/portal_backup/iptables_rules.off.bak
iptables -t nat -save > /root/portal_backup/iptables_nat.off.bak
mensaje "Reglas actuales guardadas en /root/portal_backup/"

# Limpiar todas las reglas de iptables (filter y nat) para dar paso libre
mensaje "Eliminando reglas de iptables (modo libre)..."
iptables -F
iptables -t nat -F
iptables -X

# Políticas por defecto: aceptar todo el tráfico (menos en INPUT para proteger el servidor)
iptables -P INPUT DROP
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Permitir tráfico establecido y servicios básicos en el servidor
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i $LAN_IF -p tcp --dport 22 -j ACCEPT   # SSH
iptables -A INPUT -i $LAN_IF -p udp --dport 67:68 -j ACCEPT # DHCP
iptables -A INPUT -i $LAN_IF -p udp --dport 53 -j ACCEPT   # DNS
iptables -A INPUT -i $WAN_IF -m state --state ESTABLISHED,RELATED -j ACCEPT

# NAT para dar salida a internet a todos los clientes
iptables -t nat -A POSTROUTING -o $WAN_IF -j MASQUERADE

# No redirigimos nada al portal (no hay DNAT)
# El forwarding ya es ACCEPT, así que todo pasa libremente

# Habilitar IP forwarding por si acaso
sysctl -w net.ipv4.ip_forward=1

# Reiniciar dnsmasq para que no bloquee dominios (opcional: podemos dejar el bloqueo, pero mejor desactivarlo)
# Comentamos las líneas de bloqueo en dnsmasq.conf y reiniciamos
sed -i 's/^address=\/instagram.com/0.0.0.0/#address=\/instagram.com/0.0.0.0/g' /etc/dnsmasq.conf
sed -i 's/^address=\/chatgpt.com/0.0.0.0/#address=\/chatgpt.com/0.0.0.0/g' /etc/dnsmasq.conf
systemctl restart dnsmasq

# Detener Apache (para que no interfiera, aunque no es necesario)
systemctl stop apache2

mensaje "Portal DESACTIVADO. Todos los clientes tienen acceso libre a internet."
mensaje "Para reactivar el portal, ejecuta ./portal_on.sh"
