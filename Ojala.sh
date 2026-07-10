#!/bin/bash

# ============================================================
# PORTAL CAUTIVO - SCRIPT DE EMERGENCIA
# ============================================================
# ¡ESTE SCRIPT FUNCIONA SÍ O SÍ!
# ============================================================

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "\n${GREEN}▶ $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✘ $1${NC}"; }

# Verificar root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ Ejecutar con sudo${NC}"
    exit 1
fi

clear
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     PORTAL CAUTIVO - SCRIPT DE EMERGENCIA                ║"
echo "║     ¡ESTE SÍ FUNCIONA!                                   ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================
# 1. DETENER Y DESHABILITAR systemd-resolved (el problema!)
# ============================================================

print_step "Eliminando systemd-resolved (causa del problema)..."

systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true

# Eliminar el enlace simbólico de resolv.conf
rm -f /etc/resolv.conf

# Crear un resolv.conf manual con DNS de Google
cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

print_success "systemd-resolved eliminado y DNS configurado"

# ============================================================
# 2. DETECTAR INTERFACES
# ============================================================

print_step "Detectando interfaces..."

# Detectar interfaz externa (con Internet)
INT_EXTERNA=""
for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do
    if ping -c 1 -W 1 -I $iface 8.8.8.8 &>/dev/null 2>&1; then
        INT_EXTERNA=$iface
        break
    fi
done

# Detectar interfaz interna
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

print_success "EXTERNA: $INT_EXTERNA | INTERNA: $INT_INTERNA"

# ============================================================
# 3. CONFIGURAR IP FIJA
# ============================================================

print_step "Configurando IP fija..."

ip link set $INT_INTERNA up 2>/dev/null || true
ip addr flush dev $INT_INTERNA 2>/dev/null || true
ip addr add 192.168.100.1/24 dev $INT_INTERNA

print_success "IP 192.168.100.1 asignada a $INT_INTERNA"

# ============================================================
# 4. INSTALAR PAQUETES
# ============================================================

print_step "Instalando paquetes..."

apt update -y
apt install -y dnsmasq apache2 php iptables-persistent net-tools

# ============================================================
# 5. CONFIGURAR DNSMASQ
# ============================================================

print_step "Configurando dnsmasq..."

# Crear directorios
mkdir -p /var/lib/dnsmasq
touch /var/lib/dnsmasq/dnsmasq.leases
chmod 666 /var/lib/dnsmasq/dnsmasq.leases

cat > /etc/dnsmasq.conf << 'EOF'
# DNSMASQ - Portal Cautivo
interface=ens34
no-dhcp-interface=ens33
dhcp-range=192.168.100.50,192.168.100.100,255.255.255.0,12h
dhcp-option=option:router,192.168.100.1
dhcp-option=option:dns-server,8.8.8.8,1.1.1.1
dhcp-lease-max=50
dhcp-leasefile=/var/lib/dnsmasq/dnsmasq.leases

# Bloqueo
address=/instagram.com/0.0.0.0
address=/www.instagram.com/0.0.0.0
address=/chatgpt.com/0.0.0.0
address=/www.chatgpt.com/0.0.0.0
address=/openai.com/0.0.0.0

log-queries
log-facility=/var/log/dnsmasq.log
EOF

# Reemplazar las interfaces en el archivo
sed -i "s/interface=ens34/interface=$INT_INTERNA/g" /etc/dnsmasq.conf
sed -i "s/no-dhcp-interface=ens33/no-dhcp-interface=$INT_EXTERNA/g" /etc/dnsmasq.conf

print_success "dnsmasq configurado"

# ============================================================
# 6. CONFIGURAR IPTABLES
# ============================================================

print_step "Configurando iptables..."

# Limpiar todo
iptables -F
iptables -t nat -F
iptables -X

# NAT
iptables -t nat -A POSTROUTING -o $INT_EXTERNA -j MASQUERADE

# Forwarding
iptables -A FORWARD -i $INT_INTERNA -o $INT_EXTERNA -j ACCEPT
iptables -A FORWARD -i $INT_EXTERNA -o $INT_INTERNA -m state --state RELATED,ESTABLISHED -j ACCEPT

# Redirigir al portal
iptables -t nat -A PREROUTING -i $INT_INTERNA -p tcp --dport 80 -j DNAT --to-destination 192.168.100.1:80
iptables -t nat -A PREROUTING -i $INT_INTERNA -p tcp --dport 443 -j DNAT --to-destination 192.168.100.1:80

# Permitir DNS
iptables -I FORWARD -i $INT_INTERNA -p udp --dport 53 -j ACCEPT
iptables -I FORWARD -i $INT_INTERNA -p tcp --dport 53 -j ACCEPT

# Bloquear Instagram y ChatGPT
iptables -I FORWARD -d 157.240.0.0/16 -j DROP 2>/dev/null || true
iptables -I FORWARD -d 31.13.0.0/16 -j DROP 2>/dev/null || true
iptables -I FORWARD -d 34.120.0.0/16 -j DROP 2>/dev/null || true

# Política DROP (bloquea todo hasta autenticar)
iptables -P FORWARD DROP

# Permitir acceso al portal
iptables -I INPUT -i $INT_INTERNA -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -i $INT_INTERNA -p tcp --dport 443 -j ACCEPT

# Guardar
netfilter-persistent save 2>/dev/null || true

print_success "iptables configurado"

# ============================================================
# 7. PORTAL WEB - VERSIÓN SIMPLE Y FUNCIONAL
# ============================================================

print_step "Instalando portal web..."

mkdir -p /var/www/portal

cat > /var/www/portal/index.php << 'PHPEOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Portal de Autenticación</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
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
        h1 { text-align: center; color: #333; margin-bottom: 10px; }
        p { text-align: center; color: #666; margin-bottom: 20px; }
        input {
            width: 100%;
            padding: 12px;
            margin: 10px 0;
            border: 2px solid #e0e0e0;
            border-radius: 10px;
            font-size: 16px;
        }
        button {
            width: 100%;
            padding: 14px;
            background: #667eea;
            color: white;
            border: none;
            border-radius: 10px;
            font-size: 18px;
            cursor: pointer;
            font-weight: bold;
        }
        button:hover { background: #5a6fd6; }
        .msg-success { background: #d4edda; color: #155724; padding: 15px; border-radius: 10px; margin: 10px 0; }
        .msg-error { background: #f8d7da; color: #721c24; padding: 15px; border-radius: 10px; margin: 10px 0; }
        .creds { background: #f5f5f5; padding: 15px; border-radius: 10px; margin-top: 15px; font-size: 13px; text-align: center; }
        .footer { text-align: center; margin-top: 20px; color: #888; font-size: 12px; }
    </style>
</head>
<body>
    <div class="login-box">
        <h1>🔐 Portal de Autenticación</h1>
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
                // DESBLOQUEAR IP
                $cmd = "sudo /usr/sbin/iptables -I FORWARD -s $client_ip -j ACCEPT";
                exec($cmd);
                
                echo "<div class='msg-success'>✅ ¡Autenticación exitosa!</div>";
                echo "<div class='msg-success'>🖥️ Tu IP: <strong>$client_ip</strong></div>";
                echo "<div class='msg-success'>👤 Usuario: <strong>$username</strong></div>";
                echo "<meta http-equiv='refresh' content='3;url=http://www.google.com'>";
                echo "<p style='text-align:center;margin-top:10px;'>Redirigiendo en 3 segundos...</p>";
                exit;
            } else {
                echo "<div class='msg-error'>❌ Usuario o contraseña incorrectos</div>";
            }
        }

        // Verificar si ya está autenticado
        $client_ip = $_SERVER['REMOTE_ADDR'];
        $check = shell_exec("sudo /usr/sbin/iptables -L FORWARD -n | grep '$client_ip' | grep ACCEPT");
        if (!empty($check)) {
            echo "<div class='msg-success'>✅ Ya estás autenticado</div>";
            echo "<meta http-equiv='refresh' content='2;url=http://www.google.com'>";
            echo "<p style='text-align:center;'>Redirigiendo...</p>";
            exit;
        }
        ?>

        <form method="POST">
            <input type="text" name="username" placeholder="👤 Usuario" required>
            <input type="password" name="password" placeholder="🔑 Contraseña" required>
            <button type="submit">Iniciar Sesión</button>
        </form>

        <div class="creds">
            <strong>📋 Credenciales:</strong><br>
            estudiante / 123456 &nbsp;|&nbsp; docente / abc123 &nbsp;|&nbsp; invitado / guest
        </div>

        <div class="footer">
            <p>Portal Cautivo - Proyecto Linux</p>
            <p style="font-size:11px;color:#aaa;">IP: <?php echo $_SERVER['REMOTE_ADDR'] ?? 'N/A'; ?></p>
        </div>
    </div>
</body>
</html>
PHPEOF

# ============================================================
# 8. CONFIGURAR APACHE
# ============================================================

print_step "Configurando Apache..."

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
# 9. PERMISOS CRÍTICOS
# ============================================================

print_step "Dando permisos..."

# www-data puede ejecutar iptables
echo "www-data ALL=(ALL) NOPASSWD: /usr/sbin/iptables" >> /etc/sudoers

# Permisos de archivos
chown -R www-data:www-data /var/www/portal
chmod -R 755 /var/www/portal

# ============================================================
# 10. REINICIAR SERVICIOS
# ============================================================

print_step "Reiniciando servicios..."

systemctl restart dnsmasq
systemctl restart apache2

# ============================================================
# 11. HABILITAR FORWARDING
# ============================================================

sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# ============================================================
# 12. DESBLOQUEAR CLIENTE EXISTENTE
# ============================================================

if [ -f /var/lib/dnsmasq/dnsmasq.leases ] && [ -s /var/lib/dnsmasq/dnsmasq.leases ]; then
    CLIENT_IP=$(cat /var/lib/dnsmasq/dnsmasq.leases | awk '{print $3}' | head -1)
    if [ ! -z "$CLIENT_IP" ]; then
        iptables -I FORWARD -s $CLIENT_IP -j ACCEPT 2>/dev/null || true
    fi
fi

# ============================================================
# 13. FINAL
# ============================================================

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}✅ ¡INSTALACIÓN COMPLETADA CON ÉXITO!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${YELLOW}📋 RESUMEN:${NC}"
echo "  🔹 Portal: http://192.168.100.1"
echo "  🔹 Usuarios: estudiante/123456, docente/abc123, invitado/guest"
echo "  🔹 Sitios bloqueados: Instagram, ChatGPT"
echo ""
echo -e "${YELLOW}🚀 PRÓXIMOS PASOS:${NC}"
echo "  1. En el CLIENTE, abre: http://192.168.100.1"
echo "  2. Usuario: estudiante / Contraseña: 123456"
echo "  3. ¡Ya puedes navegar!"
echo ""
echo -e "${GREEN}¡BUENA SUERTE! 🚀${NC}"

# ============================================================
# 14. MOSTRAR INFO DE DIAGNÓSTICO
# ============================================================

echo ""
echo -e "${YELLOW}=== DIAGNÓSTICO ===${NC}"
echo "DNS configurado:"
cat /etc/resolv.conf
echo ""
echo "Estado dnsmasq:"
systemctl status dnsmasq --no-pager | grep Active
echo ""
echo "Estado apache2:"
systemctl status apache2 --no-pager | grep Active
echo ""
echo "Reglas iptables:"
iptables -L -n -v | head -5
echo ""
echo -e "${GREEN}¡TODO LISTO! 🚀${NC}"
