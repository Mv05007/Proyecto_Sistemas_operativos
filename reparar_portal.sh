#!/bin/bash
# ============================================================
# Script: reparar_portal.sh
# Descripción: Repara la configuración del portal cautivo
#              (corrige IP, iptables, Apache, dnsmasq)
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
   error "Ejecuta como root: sudo ./reparar_portal.sh"
fi

# ---- Detectar interfaces ----
mensaje "Detectando interfaces..."
WAN_IF=$(ip route | grep default | awk '{print $5}' | head -1)
LAN_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -v "$WAN_IF" | head -1)

if [ -z "$WAN_IF" ] || [ -z "$LAN_IF" ]; then
    error "No se pudieron detectar WAN/LAN automáticamente. Configúralas manualmente."
fi

mensaje "WAN: $WAN_IF , LAN: $LAN_IF"

# ---- Limpiar IPs adicionales en la LAN ----
mensaje "Limpiando IPs adicionales en $LAN_IF ..."
ip addr flush dev $LAN_IF
ip addr add 192.168.10.1/24 dev $LAN_IF
ip link set $LAN_IF up

# ---- Habilitar IP forwarding ----
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# ---- Instalar paquetes (por si faltan) ----
apt update -y
apt install -y iptables dnsmasq apache2 php libapache2-mod-php at

# ---- Configurar dnsmasq ----
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

# ---- Configurar Apache ----
mkdir -p /var/www/portal
cat > /var/www/portal/index.html <<'HTML'
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Portal Cautivo</title>
<style>
body{font-family:Arial;background:#f0f0f0;display:flex;justify-content:center;align-items:center;height:100vh;}
.login-box{background:white;padding:40px;border-radius:10px;box-shadow:0 0 20px rgba(0,0,0,0.2);width:300px;}
h2{text-align:center;color:#333;}
input{width:100%;padding:10px;margin:10px 0;border:1px solid #ddd;border-radius:5px;}
input[type="submit"]{background:#28a745;color:white;border:none;cursor:pointer;}
.error{color:red;text-align:center;}
</style>
</head>
<body>
<div class="login-box">
<h2>Acceso a Internet</h2>
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
            exec("/usr/local/bin/portal_allow.sh $client_ip 2>&1");
            header('Location: /success.html'); exit;
        }
    }
    header('Location: /index.html?error=1'); exit;
}
?>
PHP

cat > /var/www/portal/success.html <<'HTML'
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Conectado</title></head>
<body style="font-family:Arial;text-align:center;padding:50px;">
<h1 style="color:green;">✅ Acceso concedido</h1>
<p>Ya puedes navegar. Sesión activa 60 minutos.</p>
<p><a href="http://google.com">Ir a Google</a></p>
</body>
</html>
HTML

# Configurar VirtualHost
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

# ---- Script de autenticación ----
mkdir -p /usr/local/bin
cat > /usr/local/bin/portal_allow.sh <<'SCRIPT'
#!/bin/bash
CLIENT_IP=$1
if [ -z "$CLIENT_IP" ]; then echo "Uso: $0 <IP>"; exit 1; fi
# Evitar duplicados
if iptables -L FORWARD -n | grep -q "$CLIENT_IP"; then
    echo "IP $CLIENT_IP ya permitida."
    exit 0
fi
# Permitir reenvío
iptables -I FORWARD -s $CLIENT_IP -j ACCEPT
# Evitar redirección al portal (DNAT)
iptables -t nat -I AUTH_IPS -s $CLIENT_IP -j RETURN
# Programar expiración (60 min)
echo "iptables -D FORWARD -s $CLIENT_IP -j ACCEPT" | at now + 60 minutes 2>/dev/null
echo "iptables -t nat -D AUTH_IPS -s $CLIENT_IP -j RETURN" | at now + 60 minutes 2>/dev/null
echo "Acceso permitido para $CLIENT_IP por 60 minutos."
SCRIPT
chmod +x /usr/local/bin/portal_allow.sh

# ---- Configurar iptables desde cero ----
mensaje "Configurando iptables..."
iptables -F
iptables -t nat -F
iptables -X

# Políticas
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Loopback y estados
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Permitir servicios en LAN
iptables -A INPUT -i $LAN_IF -p udp --dport 67:68 -j ACCEPT   # DHCP
iptables -A INPUT -i $LAN_IF -p udp --dport 53 -j ACCEPT      # DNS
iptables -A INPUT -i $LAN_IF -p tcp --dport 80 -j ACCEPT      # HTTP
iptables -A INPUT -i $LAN_IF -p icmp -j ACCEPT                # Ping
iptables -A INPUT -i $LAN_IF -p tcp --dport 22 -j ACCEPT      # SSH

# Salida a WAN
iptables -A OUTPUT -o $WAN_IF -j ACCEPT
iptables -A INPUT -i $WAN_IF -m state --state ESTABLISHED,RELATED -j ACCEPT

# NAT
iptables -t nat -A POSTROUTING -o $WAN_IF -j MASQUERADE

# Cadena AUTH_IPS para evitar redirección
iptables -t nat -N AUTH_IPS
iptables -t nat -A PREROUTING -i $LAN_IF -j AUTH_IPS

# Redirección al portal (solo para tráfico que no pasó por AUTH_IPS)
iptables -t nat -A PREROUTING -i $LAN_IF -p tcp --dport 80 -j DNAT --to-destination 192.168.10.1:80
iptables -t nat -A PREROUTING -i $LAN_IF -p tcp --dport 443 -j DNAT --to-destination 192.168.10.1:80

# Guardar reglas
apt install -y iptables-persistent
iptables-save > /etc/iptables/rules.v4
systemctl enable netfilter-persistent 2>/dev/null || systemctl enable iptables-persistent 2>/dev/null
systemctl restart netfilter-persistent 2>/dev/null || systemctl restart iptables-persistent 2>/dev/null

# ---- Asegurar atd ----
systemctl enable atd
systemctl restart atd

# ---- Resumen final ----
echo "============================================================"
echo -e "${GREEN}✅ REPARACIÓN COMPLETA${NC}"
echo "============================================================"
echo "LAN IP: 192.168.10.1/24 en $LAN_IF"
echo "DHCP: 192.168.10.100 - 192.168.10.200"
echo "Portal: http://192.168.10.1"
echo "Credenciales: admin / admin123"
echo "============================================================"
echo -e "${YELLOW}AHORA prueba desde el cliente:${NC}"
echo "1. Renueva IP (dhclient o ipconfig /renew)"
echo "2. Abre http://192.168.10.1 en el navegador"
echo "3. Deberías ver el portal de login"
echo "============================================================"
