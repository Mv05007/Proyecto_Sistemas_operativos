#!/bin/bash
# ============================================================
# portal_off.sh - Desactiva el portal cautivo y da acceso libre
# ============================================================

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

mensaje() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
advertencia() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Verificar root
if [[ $EUID -ne 0 ]]; then
   error "Ejecuta como root: sudo ./portal_off.sh"
fi

# Detectar interfaces
WAN_IF=$(ip route | grep default | awk '{print $5}' | head -1)
LAN_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -v "$WAN_IF" | head -1)

if [ -z "$WAN_IF" ] || [ -z "$LAN_IF" ]; then
    error "No se detectaron WAN/LAN automáticamente. Configura manualmente."
fi
mensaje "WAN: $WAN_IF  |  LAN: $LAN_IF"

# Guardar estado actual (por si queremos restaurar después)
BACKUP_DIR="/root/portal_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR
iptables-save > $BACKUP_DIR/iptables_backup.rules 2>/dev/null
iptables -t nat -save > $BACKUP_DIR/iptables_nat_backup.rules 2>/dev/null
mensaje "Reglas actuales guardadas en $BACKUP_DIR"

# Limpiar todas las reglas de iptables (usando el comando correcto según backend)
if command -v iptables-legacy &>/dev/null; then
    IPTABLES_CMD="iptables-legacy"
else
    IPTABLES_CMD="iptables"
fi

# Limpiar reglas
$IPTABLES_CMD -F
$IPTABLES_CMD -t nat -F
$IPTABLES_CMD -X

# Políticas por defecto: permitir todo (acceso libre)
$IPTABLES_CMD -P INPUT ACCEPT
$IPTABLES_CMD -P FORWARD ACCEPT
$IPTABLES_CMD -P OUTPUT ACCEPT

# Habilitar IP forwarding
sysctl -w net.ipv4.ip_forward=1

# Configurar NAT para salida a Internet
$IPTABLES_CMD -t nat -A POSTROUTING -o $WAN_IF -j MASQUERADE

# Detener dnsmasq (DHCP) y apache2 para que no interfieran
systemctl stop dnsmasq 2>/dev/null
systemctl stop apache2 2>/dev/null

# Si queremos, podemos dejar un DHCP simple (opcional, pero mejor dejamos que el cliente obtenga IP del router)
# En modo libre, no necesitamos dnsmasq, pero podemos dejarlo si queremos.
# En este script, lo detenemos.

mensaje "Portal DESACTIVADO. Todos los clientes tienen acceso libre a Internet."
mensaje "Para reactivar el portal, ejecuta ./portal_on.sh"
