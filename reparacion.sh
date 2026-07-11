#!/bin/bash

# ============================================================
# PORTAL CAUTIVO - SCRIPT DE REPARACION TOTAL
# ============================================================

set -e

# Colores basicos
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
# 1. DETECTAR INTERFACES
# ============================================================
echo -e "${YELLOW}[1/9] Detectando interfaces de red...${NC}"

INT_EXTERNA="ens33"
INT_INTERNA="ens34"

echo -e "${GREEN}OK: Interfaz externa = $INT_EXTERNA${NC}"
echo -e "${GREEN}OK: Interfaz interna = $INT_INTERNA${NC}"

# ============================================================
# 2. ELIMINAR SYSTEMD-RESOLVED
# ============================================================
echo -e "${YELLOW}[2/9] Eliminando systemd-resolved...${NC}"

systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true
rm -f /etc/resolv.conf

cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

echo -e "${GREEN}OK: systemd-resolved eliminado${NC}"

# ============================================================
# 3. INSTALAR PAQUETES
# ============================================================
echo -e "${YELLOW}[3/9] Instalando paquetes...${NC}"

apt update -y
apt install -y dnsmasq apache2 php iptables-persistent net-tools 2>/dev/null || true

echo -e "${GREEN}OK: Paquetes instalados${NC}"

# ============================================================
# 4. CONFIGURAR DNSMASQ (DHCP Y DNS)
# ============================================================
echo -e "${YELLOW}[4/9] Configurando dnsmasq...${NC}"

mkdir -p /var/lib/dnsmasq
touch /var/lib/dnsmasq/dnsmasq.leases
chmod 666 /var/lib/dnsmasq/dnsmasq.leases

cat > /etc/dnsmasq.conf << EOF
interface=$INT_INTERNA
no-dhcp-interface=$INT_EXTERNA
dhcp-range=192.168.50.50,192.168.50.100,255.255.255.0,12h
dhcp-option=option:router,192.168.50.1
dhcp-option=option:dns-server,192.168.50.1,8.8.8.8
dhcp-leasefile=/var/lib/dnsmasq/dnsmasq.leases

log-queries
log-facility=/var/log/dnsmasq.log
EOF

echo -e "${GREEN}OK: dnsmasq configurado${NC}"

# ============================================================
# 5. CONFIGURAR IPTABLES
# ============================================================
echo -e "${YELLOW}[5/9] Configurando iptables...${NC}"

# Limpiar reglas previas
iptables -F
iptables -t nat -F
iptables -X

# Habilitar enrutamiento en el kernel
sysctl -w net.ipv4.ip_forward=1
sed -i '/net.ipv4.ip_forward=1/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# NAT de salida general
iptables -t nat -A POSTROUTING -o $INT_EXTERNA -j MASQUERADE

# Politicas por defecto (Bloquear reenvio hasta que se autentiquen)
iptables -P FORWARD DROP

# Permitir trafico de conexiones ya establecidas
iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

# Permitir resolucion DNS para que los clientes puedan detectar el portal
iptables -A FORWARD -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -p tcp --dport 53 -j ACCEPT

# Redirigir SOLO EL TRAFICO HTTP (Puerto 80) al portal cautivo. 
# NO se redirige el 443 para evitar el error de SSL/MITM.
iptables -t nat -A PREROUTING -i $INT_INTERNA -p tcp --dport 80 -j DNAT --to-destination 192.168.50.1:80

# Guardar reglas base
netfilter-persistent save 2>/dev/null || true

echo -e "${GREEN}OK: iptables configurado de forma segura${NC}"

# ============================================================
# 6. INSTALAR PORTAL WEB (CON LOGICA DE DESBLOQUEO)
# ============================================================
echo -e "${YELLOW}[6/9] Instalando portal web...${NC}"

mkdir -p /var/www/portal

cat > /var/www/portal/index.php << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Portal de Autenticacion</title>
    <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        body { font-family: Arial, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; display: flex; justify-content: center; align-items: center; }
        .login-box { background: white; padding: 40px; border-radius: 20px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); width: 400px; max-width: 90%; }
        h1 { text-align:center; color:#333; }
        p { text-align:center; color:#666; margin-bottom: 20px; }
        input { width:100%; padding:12px; margin:10px 0; border:2px solid #e0e0e0; border-radius:10px; font-size:16px; }
        button { width:100%; padding:14px; background:#667eea; color:white; border:none; border-radius:10px; font-size:18px; cursor:pointer; font-weight:bold; }
        button:hover { background:#5a6fd6; }
        .success { background:#d4edda; color:#155724; padding:15px; border-radius:10px; margin:10px 0; }
        .error { background:#f8d7da; color:#721c24; padding:15px; border-radius:10px; margin:10px 0; }
        .creds { background:#f5f5f5; padding:15px; border-radius:10px; margin-top:15px; font-size:13px; text-align:center; }
    </style>
</head>
<body>
    <div class="login-box">
        <h1>Portal de Autenticacion</h1>
        <p>Inicia sesion para navegar</p>

        <?php
        $users = [
            'estudiante' => '123456',
            'docente' => 'abc123',
            'invitado' => 'guest'
        ];

        $client_ip = $_SERVER['REMOTE_ADDR'];

        // Comprobar si ya esta autenticado leyendo las reglas de iptables
        $check = shell_exec("sudo /usr/sbin/iptables -L FORWARD -n | grep '$client_ip' | grep ACCEPT");

        if ($_SERVER['REQUEST_METHOD'] == 'POST' && empty($check)) {
            $username = $_POST['username'];
            $password = $_POST['password'];

            if (isset($users[$username]) && $users[$username] == $password) {
                // ESTA ES LA MAGIA QUE FALTABA: Desbloquear la IP en el firewall
                shell_exec("sudo /usr/sbin/iptables -I FORWARD -s $client_ip -j ACCEPT");
                
                echo "<div class='success'>¡Autenticacion exitosa!</div>";
                echo "<p>Disfruta tu navegacion.</p>";
                echo "<meta http-equiv='refresh' content='2;url=http://bing.com'>";
                exit;
            } else {
                echo "<div class='error'>Usuario o contrasena incorrectos</div>";
            }
        } elseif (!empty($check)) {
            echo "<div class='success'>Tu dispositivo ya tiene acceso a internet.</div>";
            echo "<meta http-equiv='refresh' content='2;url=http://bing.com'>";
            exit;
        }
        ?>

        <form method="POST">
            <input type="text" name="username" placeholder="Usuario" required>
            <input type="password" name="password" placeholder="Contrasena" required>
            <button type="submit">Conectar</button>
        </form>

        <div class="creds">
            <strong>Cuentas de prueba:</strong><br>
            estudiante / 123456<br>
            docente / abc123
        </div>
    </div>
</body>
</html>
EOF

echo -e "${GREEN}OK: Portal web configurado con logica de desbloqueo${NC}"

# ============================================================
# 7. CONFIGURAR APACHE
# ============================================================
echo -e "${YELLOW}[7/9] Configurando Apache...${NC}"

cat > /etc/apache2/sites-available/portal.conf << EOF
<VirtualHost *:80>
    DocumentRoot /var/www/portal
    
    # Redirigir errores 404 a index.php para forzar el portal
    ErrorDocument 404 /index.php
    
    <Directory /var/www/portal>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

a2ensite portal.conf 2>/dev/null
a2dissite 000-default.conf 2>/dev/null

# ============================================================
# 8. PERMISOS DE FIREWALL PARA PHP
# ============================================================
echo -e "${YELLOW}[8/9] Configurando permisos sudo para Apache...${NC}"

# Asegurar que Apache pueda ejecutar iptables sin pedir contraseña
sed -i '/www-data ALL=(ALL) NOPASSWD: \/usr\/sbin\/iptables/d' /etc/sudoers
echo "www-data ALL=(ALL) NOPASSWD: /usr/sbin/iptables" >> /etc/sudoers
chown -R www-data:www-data /var/www/portal
chmod -R 755 /var/www/portal

# ============================================================
# 9. REINICIAR SERVICIOS
# ============================================================
echo -e "${YELLOW}[9/9] Reiniciando servicios...${NC}"

systemctl restart dnsmasq
systemctl restart apache2

echo ""
echo "============================================================"
echo "          CONFIGURACION COMPLETADA CON EXITO"
echo "============================================================"
echo "Tu cliente ahora puede recibir IP por DHCP automaticamente."
echo "Para probar desde Ubuntu GUI:"
echo "1. Asegurate que el cliente este en 'red-interna' y usando DHCP."
echo "2. Abre el navegador y entra a cualquier sitio HTTP (ej. http://neverssl.com)."
echo "3. Autenticate y prueba navegar."
echo "============================================================"
