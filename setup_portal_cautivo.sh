#!/bin/bash

# ============================================
# PORTAL CAUTIVO - INSTALADOR COMPLETO
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    clear
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║           PORTAL CAUTIVO - INSTALADOR                ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() { echo -e "\n${GREEN}▶ $1${NC}"; }
print_error() { echo -e "${RED}✘ ERROR: $1${NC}"; exit 1; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

print_header

if [[ $EUID -ne 0 ]]; then
   print_error "Ejecutar con sudo"
fi

echo "Interfaces disponibles:"
ip -o link show | awk -F': ' '{print "  " NR ") " $2}' | grep -v lo
echo ""

read -p "Interfaz EXTERNA (NAT) [ens33]: " INT_EXTERNA
INT_EXTERNA=${INT_EXTERNA:-ens33}

read -p "Interfaz INTERNA (red-interna) [ens34]: " INT_INTERNA
INT_INTERNA=${INT_INTERNA:-ens34}

if ! ip link show $INT_EXTERNA &> /dev/null; then
    print_error "La interfaz $INT_EXTERNA no existe"
fi

if ! ip link show $INT_INTERNA &> /dev/null; then
    print_error "La interfaz $INT_INTERNA no existe"
fi

print_success "Interfaces: EXTERNA=$INT_EXTERNA, INTERNA=$INT_INTERNA"

print_step "Instalando paquetes..."
apt update -y
apt install -y dnsmasq apache2 php iptables-persistent net-tools curl wget

print_step "Configurando red..."
NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)
[ -z "$NETPLAN_FILE" ] && NETPLAN_FILE="/etc/netplan/01-portal-netcfg.yaml"

cat > $NETPLAN_FILE << EOF
network:
  version: 2
  ethernets:
    $INT_EXTERNA:
      dhcp4: true
    $INT_INTERNA:
      dhcp4: false
      addresses:
        - 192.168.100.1/24
EOF

netplan apply

print_step "Configurando DHCP..."
cat > /etc/dnsmasq.conf << EOF
interface=$INT_INTERNA
no-dhcp-interface=$INT_EXTERNA
dhcp-range=192.168.100.50,192.168.100.100,255.255.255.0,12h
dhcp-option=option:router,192.168.100.1
dhcp-option=option:dns-server,8.8.8.8,1.1.1.1
dhcp-lease-max=50
dhcp-leasefile=/var/lib/dnsmasq/dnsmasq.leases

address=/instagram.com/0.0.0.0
address=/www.instagram.com/0.0.0.0
address=/cdninstagram.com/0.0.0.0
address=/chatgpt.com/0.0.0.0
address=/www.chatgpt.com/0.0.0.0
address=/openai.com/0.0.0.0

log-queries
log-facility=/var/log/dnsmasq.log
EOF

print_step "Configurando iptables..."
iptables -t nat -A POSTROUTING -o $INT_EXTERNA -j MASQUERADE
iptables -A FORWARD -i $INT_INTERNA -o $INT_EXTERNA -j ACCEPT
iptables -A FORWARD -i $INT_EXTERNA -o $INT_INTERNA -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -t nat -A PREROUTING -i $INT_INTERNA -p tcp --dport 80 -j DNAT --to-destination 192.168.100.1:80
iptables -t nat -A PREROUTING -i $INT_INTERNA -p tcp --dport 443 -j DNAT --to-destination 192.168.100.1:80
iptables -I FORWARD -i $INT_INTERNA -p udp --dport 53 -j ACCEPT
iptables -I FORWARD -i $INT_INTERNA -p tcp --dport 53 -j ACCEPT
iptables -I FORWARD -d 157.240.0.0/16 -j DROP 2>/dev/null || true
iptables -I FORWARD -d 31.13.0.0/16 -j DROP 2>/dev/null || true
iptables -I FORWARD -d 34.120.0.0/16 -j DROP 2>/dev/null || true
iptables -I FORWARD -d 35.190.0.0/16 -j DROP 2>/dev/null || true
iptables -P FORWARD DROP
iptables -I INPUT -i $INT_INTERNA -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -i $INT_INTERNA -p tcp --dport 443 -j ACCEPT
netfilter-persistent save

print_step "Configurando portal web..."
mkdir -p /var/www/portal

cat > /var/www/portal/index.php << 'PHPEOF'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Portal de Autenticación</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
        }
        .login-container {
            background: white;
            padding: 40px;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            width: 400px;
            max-width: 90%;
        }
        .login-header {
            text-align: center;
            margin-bottom: 30px;
        }
        .login-header h1 { font-size: 28px; color: #333; }
        .login-header p { color: #666; margin-top: 5px; }
        .logo-icon { font-size: 60px; display: block; margin-bottom: 10px; }
        .form-group { margin-bottom: 20px; }
        .form-group input {
            width: 100%;
            padding: 12px 15px;
            border: 2px solid #e0e0e0;
            border-radius: 10px;
            font-size: 16px;
        }
        .form-group input:focus {
            outline: none;
            border-color: #667eea;
        }
        .btn-login {
            width: 100%;
            padding: 14px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 10px;
            font-size: 18px;
            font-weight: 600;
            cursor: pointer;
        }
        .btn-login:hover { transform: translateY(-2px); }
        .message {
            padding: 15px;
            border-radius: 10px;
            margin-bottom: 20px;
            text-align: center;
            font-weight: 500;
        }
        .message.success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .message.error { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .message.info { background: #d1ecf1; color: #0c5460; border: 1px solid #bee5eb; }
        .credenciales {
            background: #f5f5f5;
            padding: 15px;
            border-radius: 8px;
            margin-top: 15px;
            font-size: 13px;
            color: #555;
        }
        .footer {
            text-align: center;
            margin-top: 20px;
            color: #888;
            font-size: 12px;
        }
    </style>
</head>
<body>
    <div class="login-container">
        <div class="login-header">
            <span class="logo-icon">🔐</span>
            <h1>Portal de Autenticación</h1>
            <p>Accede a la red para navegar</p>
        </div>

        <?php
        $users = [
            'estudiante' => '123456',
            'docente' => 'abc123',
            'invitado' => 'guest'
        ];

        if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['username']) && isset($_POST['password'])) {
            $username = trim($_POST['username']);
            $password = trim($_POST['password']);
            $client_ip = $_SERVER['REMOTE_ADDR'];

            if (isset($users[$username]) && $users[$username] == $password) {
                $cmd = "sudo iptables -I FORWARD -s $client_ip -j ACCEPT 2>/dev/null";
                exec($cmd);
                
                echo "<div class='message success'>✅ ¡Autenticación exitosa!</div>";
                echo "<div class='message info'>🖥️ IP: <strong>$client_ip</strong></div>";
                echo "<div class='message info'>👤 Usuario: <strong>$username</strong></div>";
                echo "<meta http-equiv='refresh' content='5;url=http://www.google.com'>";
                echo "<p style='text-align:center;'>Redirigiendo en 5 segundos...</p>";
                exit;
            } else {
                echo "<div class='message error'>❌ Usuario o contraseña incorrectos</div>";
            }
        }
        ?>

        <form method="POST">
            <div class="form-group">
                <input type="text" name="username" placeholder="👤 Usuario" required autofocus>
            </div>
            <div class="form-group">
                <input type="password" name="password" placeholder="🔑 Contraseña" required>
            </div>
            <button type="submit" class="btn-login">Iniciar Sesión</button>
        </form>

        <div class="credenciales">
            <strong>📋 Credenciales de prueba:</strong><br>
            estudiante / 123456 &nbsp;|&nbsp; docente / abc123 &nbsp;|&nbsp; invitado / guest
        </div>

        <div class="footer">
            <p>© 2024 Portal Cautivo - Proyecto Linux</p>
            <p style="font-size:11px;color:#aaa;">IP: <?php echo $_SERVER['REMOTE_ADDR'] ?? 'N/A'; ?></p>
        </div>
    </div>
</body>
</html>
PHPEOF

cat > /etc/apache2/sites-available/portal.conf << EOF
<VirtualHost *:80>
    DocumentRoot /var/www/portal
    <Directory /var/www/portal>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/portal-error.log
    CustomLog \${APACHE_LOG_DIR}/portal-access.log combined
</VirtualHost>
EOF

a2ensite portal.conf 2>/dev/null
a2dissite 000-default.conf 2>/dev/null
echo "www-data ALL=(ALL) NOPASSWD: /usr/sbin/iptables" >> /etc/sudoers
systemctl restart apache2

print_step "Reiniciando servicios..."
systemctl enable dnsmasq
systemctl restart dnsmasq
systemctl enable apache2
systemctl restart apache2

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ INSTALACIÓN COMPLETADA${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}📋 RESUMEN:${NC}"
echo "  🔹 IP del servidor: 192.168.100.1"
echo "  🔹 Portal: http://192.168.100.1"
echo "  🔹 Usuarios: estudiante/123456, docente/abc123, invitado/guest"
echo "  🔹 Sitios bloqueados: Instagram, ChatGPT"
echo ""
echo -e "${GREEN}¡Buena suerte! 🚀${NC}"
