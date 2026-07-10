#!/bin/bash

# ============================================================
# PORTAL CAUTIVO - SCRIPT DE REPARACION TOTAL
# ============================================================
# Este script desbloquea TODO el trafico del cliente
# y configura el portal correctamente

set -e

# Colores basicos
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# 1. VERIFICAR ROOT
# ============================================================

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: Ejecutar con sudo${NC}"
    exit 1
fi

clear
echo -e "${BLUE}"
echo "============================================================"
echo "        PORTAL CAUTIVO - REPARACION DEFINITIVA"
echo "============================================================"
echo -e "${NC}"

# ============================================================
# 2. DETECTAR INTERFACES
# ============================================================

echo -e "${YELLOW}[1/10] Detectando interfaces de red...${NC}"

# Interfaz externa (con internet)
INT_EXTERNA=""
for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do
    if ping -c 1 -W 1 -I $iface 8.8.8.8 &>/dev/null 2>&1; then
        INT_EXTERNA=$iface
        break
    fi
done

# Interfaz interna (red del portal)
INT_INTERNA=""
for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do
    if [ "$iface" != "$INT_EXTERNA" ]; then
        INT_INTERNA=$iface
        break
    fi
done

# Si no se detectaron, usar valores por defecto
[ -z "$INT_EXTERNA" ] && INT_EXTERNA="ens33"
[ -z "$INT_INTERNA" ] && INT_INTERNA="ens34"

echo -e "${GREEN}OK: Interfaz externa = $INT_EXTERNA${NC}"
echo -e "${GREEN}OK: Interfaz interna = $INT_INTERNA${NC}"

# ============================================================
# 3. ELIMINAR SYSTEMD-RESOLVED (CAUSA DEL PROBLEMA)
# ============================================================

echo -e "${YELLOW}[2/10] Eliminando systemd-resolved...${NC}"

systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true
rm -f /etc/resolv.conf

cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

echo -e "${GREEN}OK: systemd-resolved eliminado${NC}"

# ============================================================
# 4. CONFIGURAR IP FIJA EN INTERFAZ INTERNA
# ============================================================

echo -e "${YELLOW}[3/10] Configurando IP fija en $INT_INTERNA...${NC}"

ip link set $INT_INTERNA up 2>/dev/null || true
ip addr flush dev $INT_INTERNA 2>/dev/null || true
ip addr add 192.168.100.1/24 dev $INT_INTERNA

echo -e "${GREEN}OK: IP 192.168.100.1 asignada a $INT_INTERNA${NC}"

# ============================================================
# 5. INSTALAR PAQUETES
# ============================================================

echo -e "${YELLOW}[4/10] Instalando paquetes...${NC}"

apt update -y
apt install -y dnsmasq apache2 php iptables-persistent net-tools 2>/dev/null || true

echo -e "${GREEN}OK: Paquetes instalados${NC}"

# ============================================================
# 6. CONFIGURAR DNSMASQ
# ============================================================

echo -e "${YELLOW}[5/10] Configurando dnsmasq...${NC}"

mkdir -p /var/lib/dnsmasq
touch /var/lib/dnsmasq/dnsmasq.leases
chmod 666 /var/lib/dnsmasq/dnsmasq.leases

cat > /etc/dnsmasq.conf << EOF
interface=$INT_INTERNA
no-dhcp-interface=$INT_EXTERNA
dhcp-range=192.168.100.50,192.168.100.100,255.255.255.0,12h
dhcp-option=option:router,192.168.100.1
dhcp-option=option:dns-server,8.8.8.8,1.1.1.1
dhcp-leasefile=/var/lib/dnsmasq/dnsmasq.leases

address=/instagram.com/0.0.0.0
address=/www.instagram.com/0.0.0.0
address=/chatgpt.com/0.0.0.0
address=/www.chatgpt.com/0.0.0.0
address=/openai.com/0.0.0.0

log-queries
log-facility=/var/log/dnsmasq.log
EOF

echo -e "${GREEN}OK: dnsmasq configurado${NC}"

# ============================================================
# 7. LIMPIAR Y CONFIGURAR IPTABLES
# ============================================================

echo -e "${YELLOW}[6/10] Configurando iptables...${NC}"

# Limpiar todo
iptables -F
iptables -t nat -F
iptables -X
iptables -t nat -X

# Habilitar forwarding
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# NAT
iptables -t nat -A POSTROUTING -o $INT_EXTERNA -j MASQUERADE

# Forwarding basico
iptables -P FORWARD ACCEPT
iptables -A FORWARD -i $INT_INTERNA -o $INT_EXTERNA -j ACCEPT
iptables -A FORWARD -i $INT_EXTERNA -o $INT_INTERNA -m state --state RELATED,ESTABLISHED -j ACCEPT

# Redirigir al portal (HTTP y HTTPS)
iptables -t nat -A PREROUTING -i $INT_INTERNA -p tcp --dport 80 -j DNAT --to-destination 192.168.100.1:80
iptables -t nat -A PREROUTING -i $INT_INTERNA -p tcp --dport 443 -j DNAT --to-destination 192.168.100.1:80

# DNS
iptables -I FORWARD -i $INT_INTERNA -p udp --dport 53 -j ACCEPT
iptables -I FORWARD -i $INT_INTERNA -p tcp --dport 53 -j ACCEPT

# Bloquear sitios
iptables -I FORWARD -d 157.240.0.0/16 -j DROP 2>/dev/null || true
iptables -I FORWARD -d 31.13.0.0/16 -j DROP 2>/dev/null || true
iptables -I FORWARD -d 34.120.0.0/16 -j DROP 2>/dev/null || true
iptables -I FORWARD -d 35.190.0.0/16 -j DROP 2>/dev/null || true

# Permitir acceso al portal
iptables -I INPUT -i $INT_INTERNA -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -i $INT_INTERNA -p tcp --dport 443 -j ACCEPT

# DESBLOQUEAR TODO EL RANGO DEL CLIENTE (SOLUCION DEFINITIVA)
iptables -I FORWARD -s 192.168.100.0/24 -j ACCEPT

# Guardar reglas
netfilter-persistent save 2>/dev/null || true

echo -e "${GREEN}OK: iptables configurado y rango 192.168.100.0/24 desbloqueado${NC}"

# ============================================================
# 8. INSTALAR PORTAL WEB
# ============================================================

echo -e "${YELLOW}[7/10] Instalando portal web...${NC}"

mkdir -p /var/www/portal

cat > /var/www/portal/index.php << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Portal de Autenticacion</title>
    <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        body {
            font-family: Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
        }
        .login-box {
            background: white;
            padding: 40px;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            width: 400px;
            max-width: 90%;
        }
        h1 { text-align:center; color:#333; }
        p { text-align:center; color:#666; }
        input {
            width:100%;
            padding:12px;
            margin:10px 0;
            border:2px solid #e0e0e0;
            border-radius:10px;
            font-size:16px;
        }
        button {
            width:100%;
            padding:14px;
            background:#667eea;
            color:white;
            border:none;
            border-radius:10px;
            font-size:18px;
            cursor:pointer;
            font-weight:bold;
        }
        button:hover { background:#5a6fd6; }
        .success { background:#d4edda; color:#155724; padding:15px; border-radius:10px; margin:10px 0; }
        .error { background:#f8d7da; color:#721c24; padding:15px; border-radius:10px; margin:10px 0; }
        .creds { background:#f5f5f5; padding:15px; border-radius:10px; margin-top:15px; font-size:13px; text-align:center; }
        .footer { text-align:center; margin-top:20px; color:#888; font-size:12px; }
    </style>
</head>
<body>
    <div class="login-box">
        <h1>Portal de Autenticacion</h1>
        <p>Accede a la red para navegar</p>

        <?php
        $users = [
            'estudiante' => '123456',
            'docente' => 'abc123',
            'invitado' => 'guest'
        ];

        if ($_SERVER['REQUEST_METHOD'] == 'POST') {
            $username = $_POST['username'];
            $password = $_POST['password'];
            $client_ip = $_SERVER['REMOTE_ADDR'];

            if (isset($users[$username]) && $users[$username] == $password) {
                echo "<div class='success'>Autenticacion exitosa</div>";
                echo "<div class='success'>IP: $client_ip</div>";
                echo "<div class='success'>Usuario: $username</div>";
                echo "<meta http-equiv='refresh' content='2;url=http://bing.com'>";
                echo "<p style='text-align:center;margin-top:10px;'>Redirigiendo a Bing...</p>";
                exit;
            } else {
                echo "<div class='error'>Usuario o contrasena incorrectos</div>";
            }
        }

        $client_ip = $_SERVER['REMOTE_ADDR'];
        $check = shell_exec("sudo /usr/sbin/iptables -L FORWARD -n | grep '$client_ip' | grep ACCEPT");
        if (!empty($check)) {
            echo "<div class='success'>Ya estas autenticado</div>";
            echo "<meta http-equiv='refresh' content='1;url=http://bing.com'>";
            echo "<p style='text-align:center;'>Redirigiendo...</p>";
            exit;
        }
        ?>

        <form method="POST">
            <input type="text" name="username" placeholder="Usuario" required>
            <input type="password" name="password" placeholder="Contrasena" required>
            <button type="submit">Iniciar Sesion</button>
        </form>

        <div class="creds">
            <strong>Credenciales:</strong><br>
            estudiante / 123456 | docente / abc123 | invitado / guest
        </div>

        <div class="footer">
            <p>Portal Cautivo - Proyecto Linux</p>
            <p>IP: <?php echo $_SERVER['REMOTE_ADDR'] ?? 'N/A'; ?></p>
        </div>
    </div>
</body>
</html>
EOF

echo -e "${GREEN}OK: Portal web instalado${NC}"

# ============================================================
# 9. CONFIGURAR APACHE
# ============================================================

echo -e "${YELLOW}[8/10] Configurando Apache...${NC}"

cat > /etc/apache2/sites-available/portal.conf << EOF
<VirtualHost *:80>
    DocumentRoot /var/www/portal
    <Directory /var/www/portal>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

a2ensite portal.conf 2>/dev/null
a2dissite 000-default.conf 2>/dev/null

# ============================================================
# 10. PERMISOS
# ============================================================

echo -e "${YELLOW}[9/10] Dando permisos...${NC}"

echo "www-data ALL=(ALL) NOPASSWD: /usr/sbin/iptables" >> /etc/sudoers
chown -R www-data:www-data /var/www/portal
chmod -R 755 /var/www/portal

# ============================================================
# 11. REINICIAR SERVICIOS
# ============================================================

echo -e "${YELLOW}[10/10] Reiniciando servicios...${NC}"

systemctl restart dnsmasq
systemctl restart apache2

# ============================================================
# 12. VERIFICACION FINAL
# ============================================================

echo ""
echo "============================================================"
echo "VERIFICACION FINAL"
echo "============================================================"

echo ""
echo "Servicios:"
systemctl status dnsmasq --no-pager | grep "Active:"
systemctl status apache2 --no-pager | grep "Active:"

echo ""
echo "Interfaz interna:"
ip addr show $INT_INTERNA | grep inet

echo ""
echo "Reglas iptables:"
iptables -L FORWARD -n -v | head -10

echo ""
echo "Clientes DHCP:"
cat /var/lib/dnsmasq/dnsmasq.leases 2>/dev/null || echo "  No hay clientes"

echo ""
echo "============================================================"
echo "REPARACION COMPLETADA"
echo "============================================================"
echo ""
echo "EN EL CLIENTE:"
echo "1. Configura IP fija:"
echo "   Direccion: 192.168.100.72"
echo "   Mascara: 255.255.255.0"
echo "   Puerta de enlace: 192.168.100.1"
echo "   DNS: 8.8.8.8"
echo ""
echo "2. Abre navegador y ve a: http://192.168.100.1"
echo ""
echo "3. Autenticate con: estudiante / 123456"
echo ""
echo "4. Despues de autenticar, ve a: http://bing.com"
echo ""
echo "5. Si aun no funciona, ejecuta en el CLIENTE:"
echo "   sudo ip route add default via 192.168.100.1"
echo ""
echo "============================================================"
