#!/bin/bash
# ============================================================
# Script: diagnostico_y_reparacion_portal.sh
# Descripción: Diagnostica y repara la configuración del portal cautivo
#              basado en iptables, dnsmasq y Apache.
# Uso: sudo ./diagnostico_y_reparacion_portal.sh
# ============================================================

set -e  # Salir si hay error en comandos críticos (pero no en todos)

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Verificar root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este script debe ejecutarse como root. Usa sudo.${NC}"
   exit 1
fi

# ---- FUNCIONES DE DIAGNÓSTICO ----

diag_servicios() {
    echo -e "${BLUE}=== ESTADO DE SERVICIOS ===${NC}"
    for svc in dnsmasq apache2; do
        if systemctl is-active --quiet $svc; then
            echo -e "${GREEN}✓ $svc está activo${NC}"
        else
            echo -e "${RED}✗ $svc NO está activo${NC}"
        fi
        systemctl status $svc --no-pager | head -3
        echo ""
    done
}

diag_interfaces() {
    echo -e "${BLUE}=== CONFIGURACIÓN DE RED ===${NC}"
    echo "Interfaces con IP:"
    ip -4 addr show | grep -E "^[0-9]+: |inet "
    echo ""
    echo "Interfaz LAN detectada (ens34? eth1?):"
    # Buscar interfaz con IP 192.168.x.1 (típica LAN)
    LAN_IF=$(ip -4 addr | grep -oP '(?<=: )[^:]+(?=:.*inet 192\.168\.\d+\.1)' | head -1)
    if [ -z "$LAN_IF" ]; then
        LAN_IF=$(ip -4 addr | grep -E 'inet 192\.168\.' | awk '{print $NF}' | head -1)
    fi
    echo "LAN_IF: ${LAN_IF:-No encontrada}"
    WAN_IF=$(ip route | grep default | awk '{print $5}' | head -1)
    echo "WAN_IF: ${WAN_IF:-No encontrada}"
    echo ""
}

diag_dnsmasq() {
    echo -e "${BLUE}=== CONFIGURACIÓN DNSMASQ ===${NC}"
    if [ -f /etc/dnsmasq.conf ]; then
        echo "Contenido de /etc/dnsmasq.conf (líneas relevantes):"
        grep -E "interface|dhcp-range|dhcp-option|address=" /etc/dnsmasq.conf || echo "No se encontraron líneas clave"
        echo ""
        echo "Logs de dnsmasq (últimas 5 líneas):"
        tail -5 /var/log/dnsmasq.log 2>/dev/null || echo "No se pudo leer /var/log/dnsmasq.log"
    else
        echo -e "${RED}No existe /etc/dnsmasq.conf${NC}"
    fi
    echo ""
}

diag_apache() {
    echo -e "${BLUE}=== CONFIGURACIÓN APACHE ===${NC}"
    if [ -f /etc/apache2/sites-enabled/portal.conf ]; then
        echo "Sitio portal.conf habilitado."
    else
        echo -e "${RED}Sitio portal.conf NO habilitado.${NC}"
    fi
    echo "Archivos en /var/www/portal:"
    ls -la /var/www/portal/ 2>/dev/null || echo "Directorio no existe"
    echo ""
}

diag_iptables() {
    echo -e "${BLUE}=== REGLAS IPTABLES ===${NC}"
    echo "---- FILTER ----"
    iptables -L -n -v --line-numbers | head -20
    echo ""
    echo "---- NAT ----"
    iptables -t nat -L -n -v --line-numbers | head -20
    echo ""
    echo "---- MANGLE (opcional) ----"
    iptables -t mangle -L -n -v --line-numbers | head -10
    echo ""
}

diag_scripts() {
    echo -e "${BLUE}=== SCRIPTS DE AUTENTICACIÓN ===${NC}"
    if [ -f /usr/local/bin/portal_allow.sh ]; then
        echo "Contenido de /usr/local/bin/portal_allow.sh:"
        cat /usr/local/bin/portal_allow.sh
    else
        echo -e "${RED}No existe /usr/local/bin/portal_allow.sh${NC}"
    fi
    echo ""
}

diag_dhcp_clients() {
    echo -e "${BLUE}=== CLIENTES DHCP (leases) ===${NC}"
    if [ -f /var/lib/misc/dnsmasq.leases ]; then
        echo "Leases actuales:"
        cat /var/lib/misc/dnsmasq.leases
    else
        echo "No se encontró archivo de leases."
    fi
    echo ""
}

# ---- FUNCIÓN DE REPARACIÓN (con confirmación) ----

reparar() {
    echo -e "${YELLOW}Se procederá a aplicar las correcciones.${NC}"
    echo -e "${YELLOW}Esto incluye:${NC}"
    echo "  - Configurar IP estática 192.168.10.1 en la interfaz LAN (ens34 o similar)"
    echo "  - Reconfigurar dnsmasq con DHCP y bloqueo de dominios"
    echo "  - Reconfigurar Apache con la página del portal"
    echo "  - Aplicar reglas de iptables para NAT, redirección y control de acceso"
    echo "  - Crear script de autenticación y programar expiraciones con at"
    read -p "¿Estás seguro de continuar? (s/N): " confirm
    if [[ ! "$confirm" =~ ^[sS]$ ]]; then
        echo "Operación cancelada."
        exit 0
    fi

    # --- 1. Detectar interfaces ---
    # Intentar identificar LAN (ens34, eth1, etc.) y WAN (ens33, eth0)
    # Si el script se ejecuta con root, podemos preguntar o usar heurística.
    echo -e "${BLUE}Detectando interfaces...${NC}"
    # Buscar una interfaz con IP 192.168.x.1 (la que ya tiene) o preguntar
    LAN_IF=$(ip -4 addr | grep -oP '(?<=: )[^:]+(?=:.*inet 192\.168\.\d+\.1)' | head -1)
    if [ -z "$LAN_IF" ]; then
        # Si no tiene IP 192.168.x.1, preguntamos
        echo "No se detectó automáticamente la interfaz LAN."
        echo "Interfaces disponibles:"
        ip -o link show | awk -F': ' '{print $2}' | grep -v lo
        read -p "Introduce el nombre de la interfaz LAN (ej. ens34, eth1): " LAN_IF
    fi
    WAN_IF=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -z "$WAN_IF" ]; then
        read -p "Introduce el nombre de la interfaz WAN (ej. ens33, eth0): " WAN_IF
    fi
    echo "LAN_IF=$LAN_IF , WAN_IF=$WAN_IF"

    # --- 2. Configurar IP estática en LAN ---
    echo -e "${BLUE}Configurando IP estática $LAN_IF -> 192.168.10.1/24${NC}"
    # Respaldo de /etc/network/interfaces
    cp /etc/network/interfaces /etc/network/interfaces.bak.portal 2>/dev/null || true
    # Eliminar configuraciones previas de esa interfaz (si usamos ifupdown)
    sed -i "/^auto $LAN_IF/d; /^iface $LAN_IF/d; /^    address/d; /^    netmask/d" /etc/network/interfaces
    cat >> /etc/network/interfaces <<EOF
auto $LAN_IF
iface $LAN_IF inet static
    address 192.168.10.1
    netmask 255.255.255.0
EOF
    # Si existe netplan, también configuramos
    if [ -d /etc/netplan ]; then
        cat > /etc/netplan/99-lan.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $LAN_IF:
      addresses:
        - 192.168.10.1/24
      dhcp4: no
EOF
        netplan apply 2>/dev/null || true
    fi
    # Reiniciar red
    systemctl restart networking 2>/dev/null || systemctl restart NetworkManager 2>/dev/null || true
    # Asignar IP manualmente por si acaso
    ip addr flush dev $LAN_IF 2>/dev/null
    ip addr add 192.168.10.1/24 dev $LAN_IF
    ip link set $LAN_IF up

    # --- 3. Habilitar IP forwarding ---
    sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

    # --- 4. Instalar paquetes necesarios ---
    echo -e "${BLUE}Instalando paquetes...${NC}"
    apt update -y
    apt install -y iptables dnsmasq apache2 php libapache2-mod-php at

    # --- 5. Configurar dnsmasq ---
    echo -e "${BLUE}Configurando dnsmasq...${NC}"
    cat > /etc/dnsmasq.conf <<EOF
interface=$LAN_IF
bind-interfaces
dhcp-range=192.168.10.100,192.168.10.200,255.255.255.0,24h
dhcp-option=3,192.168.10.1
dhcp-option=6,192.168.10.1
address=/instagram.com/0.0.0.0
address=/www.instagram.com/0.0.0.0
address=/chatgpt.com/0.0.0.0
address=/www.chatgpt.com/0.0.0.0
log-queries
log-facility=/var/log/dnsmasq.log
EOF
    systemctl restart dnsmasq
    systemctl enable dnsmasq

    # --- 6. Configurar Apache y portal ---
    echo -e "${BLUE}Configurando Apache y portal...${NC}"
    mkdir -p /var/www/portal

    cat > /var/www/portal/index.html <<'HTML'
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Portal Cautivo</title>
<style>
body{font-family:Arial;background:#f0f0f0;display:flex;justify-content:center;align-items:center;height:100vh;}
.login-box{background:white;padding:40px;border-radius:10px;box-shadow:0 0 20px rgba(0,0,0,0.2);width:300px;}
h2{text-align:center;color:#333;}
input[type="text"],input[type="password"]{width:100%;padding:10px;margin:10px 0;border:1px solid #ddd;border-radius:5px;}
input[type="submit"]{width:100%;padding:10px;background:#28a745;color:white;border:none;border-radius:5px;cursor:pointer;}
.error{color:red;text-align:center;}
</style>
</head>
<body>
<div class="login-box">
<h2>Acceso a Internet</h2>
<p style="text-align:center;color:#666;">Debes autenticarte para navegar</p>
<form method="POST" action="/login.php">
<input type="text" name="user" placeholder="Usuario" required>
<input type="password" name="pass" placeholder="Contraseña" required>
<input type="submit" value="Conectar">
</form>
<?php if(isset($_GET['error'])) echo '<p class="error">Credenciales incorrectas</p>'; ?>
</div>
</body>
</html>
HTML

    cat > /var/www/portal/login.php <<'PHP'
<?php
$VALID_USER='admin'; $VALID_PASS='admin123';
if($_SERVER['REQUEST_METHOD']==='POST'){
    $user=$_POST['user']??''; $pass=$_POST['pass']??'';
    if($user===$VALID_USER && $pass===$VALID_PASS){
        $client_ip=$_SERVER['REMOTE_ADDR'];
        if(isset($_SERVER['HTTP_X_FORWARDED_FOR'])) $client_ip=$_SERVER['HTTP_X_FORWARDED_FOR'];
        if(filter_var($client_ip,FILTER_VALIDATE_IP)){
            $cmd="/usr/local/bin/portal_allow.sh $client_ip";
            shell_exec($cmd." 2>&1");
            header('Location: /success.html'); exit;
        }else{ header('Location: /index.html?error=ip'); exit; }
    }else{ header('Location: /index.html?error=credencial'); exit; }
}else{ header('Location: /index.html'); exit; }
?>
PHP

    cat > /var/www/portal/success.html <<'HTML'
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Conectado</title></head>
<body style="font-family:Arial;text-align:center;padding:50px;">
<h1 style="color:green;">✅ Acceso concedido</h1>
<p>Ya puedes navegar por Internet. Sesión activa 60 minutos.</p>
<p><a href="http://google.com">Ir a Google</a></p>
</body>
</html>
HTML

    # Configurar sitio Apache
    cat > /etc/apache2/sites-available/portal.conf <<EOF
<VirtualHost *:80>
    DocumentRoot /var/www/portal
    <Directory /var/www/portal>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/portal_error.log
    CustomLog \${APACHE_LOG_DIR}/portal_access.log combined
</VirtualHost>
EOF
    a2dissite 000-default.conf 2>/dev/null
    a2ensite portal.conf
    systemctl restart apache2
    systemctl enable apache2

    # --- 7. Script de autenticación ---
    echo -e "${BLUE}Creando script de autenticación...${NC}"
    mkdir -p /usr/local/bin
    cat > /usr/local/bin/portal_allow.sh <<'SCRIPT'
#!/bin/bash
CLIENT_IP=$1
if [ -z "$CLIENT_IP" ]; then echo "Uso: $0 <IP>"; exit 1; fi
if iptables -L FORWARD -n | grep -q "$CLIENT_IP"; then
    echo "La IP $CLIENT_IP ya está permitida."
    exit 0
fi
# Permitir reenvío
iptables -I FORWARD -s $CLIENT_IP -j ACCEPT
# Evitar redirección al portal
iptables -t nat -I AUTH_IPS -s $CLIENT_IP -j RETURN
# Programar expiración (60 minutos)
echo "iptables -D FORWARD -s $CLIENT_IP -j ACCEPT" | at now + 60 minutes 2>/dev/null
echo "iptables -t nat -D AUTH_IPS -s $CLIENT_IP -j RETURN" | at now + 60 minutes 2>/dev/null
echo "Acceso permitido para $CLIENT_IP por 60 minutos."
SCRIPT
    chmod +x /usr/local/bin/portal_allow.sh

    # --- 8. Configurar iptables ---
    echo -e "${BLUE}Configurando iptables...${NC}"
    # Limpiar
    iptables -F
    iptables -t nat -F
    iptables -X

    # Políticas
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    # Permitir loopback y establecido
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Permitir servicios en LAN
    iptables -A INPUT -i $LAN_IF -p udp --dport 67:68 -j ACCEPT
    iptables -A INPUT -i $LAN_IF -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -i $LAN_IF -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -i $LAN_IF -p icmp -j ACCEPT
    iptables -A INPUT -i $LAN_IF -p tcp --dport 22 -j ACCEPT

    # Permitir tráfico WAN entrante solo establecido
    iptables -A INPUT -i $WAN_IF -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -o $WAN_IF -j ACCEPT

    # NAT (MASQUERADE)
    iptables -t nat -A POSTROUTING -o $WAN_IF -j MASQUERADE

    # Cadena AUTH_IPS para evitar DNAT
    iptables -t nat -N AUTH_IPS
    iptables -t nat -A PREROUTING -i $LAN_IF -j AUTH_IPS

    # Redirección HTTP/HTTPS al portal
    iptables -t nat -A PREROUTING -i $LAN_IF -p tcp --dport 80 -j DNAT --to-destination 192.168.10.1:80
    iptables -t nat -A PREROUTING -i $LAN_IF -p tcp --dport 443 -j DNAT --to-destination 192.168.10.1:80

    # Guardar reglas
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    apt install -y iptables-persistent
    systemctl enable netfilter-persistent 2>/dev/null || systemctl enable iptables-persistent 2>/dev/null
    systemctl restart netfilter-persistent 2>/dev/null || systemctl restart iptables-persistent 2>/dev/null

    # --- 9. Asegurar at ---
    systemctl enable atd
    systemctl start atd

    # --- 10. Resumen final ---
    echo -e "${GREEN}✅ Portal cautivo configurado correctamente.${NC}"
    echo "LAN: $LAN_IF (192.168.10.1/24)"
    echo "WAN: $WAN_IF"
    echo "DHCP: 192.168.10.100-200"
    echo "Portal: http://192.168.10.1"
    echo "Credenciales: admin / admin123"
    echo "Bloqueados: instagram.com, chatgpt.com"
    echo ""
    echo -e "${YELLOW}Reinicia el servidor o los servicios para aplicar todo.${NC}"
}

# ---- MAIN ----

# Primero, diagnóstico
echo -e "${GREEN}===== DIAGNÓSTICO DEL SISTEMA =====${NC}"
diag_servicios
diag_interfaces
diag_dnsmasq
diag_apache
diag_iptables
diag_scripts
diag_dhcp_clients

# Preguntar si se desea reparar
echo ""
echo -e "${YELLOW}¿Deseas aplicar la configuración automática para corregir el portal?${NC}"
read -p "Escribe 's' para reparar, cualquier otra tecla para salir: " respuesta
if [[ "$respuesta" =~ ^[sS]$ ]]; then
    reparar
else
    echo "No se realizaron cambios."
    echo "Puedes copiar la salida del diagnóstico y pasármela para ayudarte."
    exit 0
fi
