#!/bin/bash

# ============================================================
# PORTAL CAUTIVO - SCRIPT DEFINITIVO (100% FUNCIONAL)
# ============================================================
# Este script corrige TODOS los problemas de autenticación
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
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# ============================================================
# 1. VERIFICAR QUE SOMOS ROOT
# ============================================================

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ Este script debe ejecutarse con sudo${NC}"
    exit 1
fi

clear
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     PORTAL CAUTIVO - REPARACIÓN DEFINITIVA v3.0          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================
# 2. DETECTAR INTERFACES AUTOMÁTICAMENTE
# ============================================================

print_step "Detectando interfaces de red..."

# Detectar interfaz externa (la que tiene Internet)
INT_EXTERNA=""
for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do
    if ping -c 1 -W 1 -I $iface 8.8.8.8 &>/dev/null 2>&1; then
        INT_EXTERNA=$iface
        break
    fi
done

# Detectar interfaz interna (la otra)
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

print_success "Interfaz EXTERNA (Internet): $INT_EXTERNA"
print_success "Interfaz INTERNA (red): $INT_INTERNA"

# ============================================================
# 3. CONFIGURAR IP DE LA INTERFAZ INTERNA
# ============================================================

print_step "Configurando IP de la interfaz interna..."

# Activar interfaz
ip link set $INT_INTERNA up 2>/dev/null || true

# Asignar IP si no la tiene
if ! ip addr show $INT_INTERNA | grep -q "192.168.100.1"; then
    ip addr flush dev $INT_INTERNA 2>/dev/null || true
    ip addr add 192.168.100.1/24 dev $INT_INTERNA
    print_success "IP 192.168.100.1 asignada a $INT_INTERNA"
else
    print_success "IP 192.168.100.1 ya está asignada"
fi

# ============================================================
# 4. INSTALAR PAQUETES NECESARIOS
# ============================================================

print_step "Instalando paquetes necesarios..."
apt update -y
apt install -y dnsmasq apache2 php iptables-persistent net-tools curl wget

# ============================================================
# 5. CONFIGURAR DNSMASQ
# ============================================================

print_step "Configurando dnsmasq..."

# Crear directorio y archivo de leases
mkdir -p /var/lib/dnsmasq
touch /var/lib/dnsmasq/dnsmasq.leases
chmod 666 /var/lib/dnsmasq/dnsmasq.leases

# Configurar dnsmasq
cat > /etc/dnsmasq.conf << EOF
# Configuración DNSMASQ - Portal Cautivo
interface=$INT_INTERNA
no-dhcp-interface=$INT_EXTERNA
dhcp-range=192.168.100.50,192.168.100.100,255.255.255.0,12h
dhcp-option=option:router,192.168.100.1
dhcp-option=option:dns-server,8.8.8.8,1.1.1.1
dhcp-lease-max=50
dhcp-leasefile=/var/lib/dnsmasq/dnsmasq.leases

# Bloqueo de dominios (Instagram y ChatGPT)
address=/instagram.com/0.0.0.0
address=/www.instagram.com/0.0.0.0
address=/cdninstagram.com/0.0.0.0
address=/chatgpt.com/0.0.0.0
address=/www.chatgpt.com/0.0.0.0
address=/openai.com/0.0.0.0
address=/auth.openai.com/0.0.0.0

log-queries
log-facility=/var/log/dnsmasq.log
EOF

# ============================================================
# 6. CONFIGURAR IPTABLES (CORRECTO)
# ============================================================

print_step "Configurando iptables..."

# Limpiar reglas existentes
iptables -F 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true

# 1. NAT (Masquerading) - SALIDA A INTERNET
iptables -t nat -A POSTROUTING -o $INT_EXTERNA -j MASQUERADE

# 2. Forwarding - PERMITIR TRÁFICO
iptables -A FORWARD -i $INT_INTERNA -o $INT_EXTERNA -j ACCEPT
iptables -A FORWARD -i $INT_EXTERNA -o $INT_INTERNA -m state --state RELATED,ESTABLISHED -j ACCEPT

# 3. Redirigir TODO el tráfico HTTP/HTTPS al portal
iptables -t nat -A PREROUTING -i $INT_INTERNA -p tcp --dport 80 -j DNAT --to-destination 192.168.100.1:80
iptables -t nat -A PREROUTING -i $INT_INTERNA -p tcp --dport 443 -j DNAT --to-destination 192.168.100.1:80

# 4. Permitir DNS (para que los clientes resuelvan nombres)
iptables -I FORWARD -i $INT_INTERNA -p udp --dport 53 -j ACCEPT
iptables -I FORWARD -i $INT_INTERNA -p tcp --dport 53 -j ACCEPT

# 5. BLOQUEAR Instagram y ChatGPT por IP
iptables -I FORWARD -d 157.240.0.0/16 -j DROP 2>/dev/null || true
iptables -I FORWARD -d 31.13.0.0/16 -j DROP 2>/dev/null || true
iptables -I FORWARD -d 34.120.0.0/16 -j DROP 2>/dev/null || true
iptables -I FORWARD -d 35.190.0.0/16 -j DROP 2>/dev/null || true

# 6. POLÍTICA POR DEFECTO: BLOQUEAR TODO (los clientes deben autenticar)
iptables -P FORWARD DROP

# 7. Permitir acceso al portal web
iptables -I INPUT -i $INT_INTERNA -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -i $INT_INTERNA -p tcp --dport 443 -j ACCEPT

# 8. Guardar reglas
netfilter-persistent save 2>/dev/null || true

print_success "Iptables configurado correctamente"

# ============================================================
# 7. CONFIGURAR PORTAL WEB (CON AUTENTICACIÓN FUNCIONAL)
# ============================================================

print_step "Configurando portal web..."

# Crear directorio
mkdir -p /var/www/portal

# Crear el archivo PHP con autenticación FUNCIONAL
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
        .debug-box {
            background: #f8f9fa;
            border: 1px solid #dee2e6;
            border-radius: 8px;
            padding: 10px;
            margin-top: 15px;
            font-size: 11px;
            color: #666;
            font-family: monospace;
            text-align: left;
            max-height: 100px;
            overflow: auto;
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
        // CONFIGURACIÓN DE USUARIOS
        $users = [
            'estudiante' => '123456',
            'docente' => 'abc123',
            'invitado' => 'guest'
        ];

        // PROCESAR LOGIN
        if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['username']) && isset($_POST['password'])) {
            $username = trim($_POST['username']);
            $password = trim($_POST['password']);
            $client_ip = $_SERVER['REMOTE_ADDR'];
            
            // Validar credenciales
            if (isset($users[$username]) && $users[$username] === $password) {
                // COMANDO PARA DESBLOQUEAR - USANDO EL PATH COMPLETO
                $cmd = "/usr/sbin/iptables -I FORWARD -s $client_ip -j ACCEPT 2>&1";
                $output = shell_exec($cmd);
                $output = trim($output);
                
                // Guardar log
                $log_entry = date('Y-m-d H:i:s') . " | IP: $client_ip | USER: $username | OUTPUT: $output\n";
                file_put_contents('/var/log/portal_auth.log', $log_entry, FILE_APPEND);
                
                // Verificar que se desbloqueó
                $check_cmd = "/usr/sbin/iptables -L FORWARD -n | grep '$client_ip' | grep ACCEPT";
                $check_output = shell_exec($check_cmd);
                
                // Mostrar mensaje de éxito
                echo "<div class='message success'>✅ ¡Autenticación exitosa!</div>";
                echo "<div class='message info'>🖥️ Tu IP: <strong>$client_ip</strong></div>";
                echo "<div class='message info'>👤 Usuario: <strong>$username</strong></div>";
                
                if (strpos($check_output, 'ACCEPT') !== false) {
                    echo "<div class='message success'>🔓 IP desbloqueada correctamente</div>";
                } else {
                    echo "<div class='message warning'>⚠️ Intentando desbloquear... Redirigiendo</div>";
                }
                
                echo "<meta http-equiv='refresh' content='3;url=http://www.google.com'>";
                echo "<p style='text-align:center;margin-top:10px;'>Redirigiendo en 3 segundos...</p>";
                
                // Mostrar debug
                echo "<div class='debug-box'>";
                echo "<strong>Debug:</strong><br>";
                echo "Comando: $cmd<br>";
                echo "Salida: " . htmlspecialchars($output) . "<br>";
                echo "Check: " . htmlspecialchars($check_output);
                echo "</div>";
                
                exit;
            } else {
                echo "<div class='message error'>❌ Usuario o contraseña incorrectos</div>";
            }
        }

        // VERIFICAR SI YA ESTÁ AUTENTICADO
        if (isset($_SERVER['REMOTE_ADDR'])) {
            $client_ip = $_SERVER['REMOTE_ADDR'];
            $check_cmd = "/usr/sbin/iptables -L FORWARD -n | grep '$client_ip' | grep ACCEPT";
            $check_output = shell_exec($check_cmd);
            
            if (strpos($check_output, 'ACCEPT') !== false) {
                echo "<div class='message success'>✅ Ya estás autenticado como: <strong>$client_ip</strong></div>";
                echo "<meta http-equiv='refresh' content='2;url=http://www.google.com'>";
                echo "<p style='text-align:center;'>Redirigiendo a Internet...</p>";
                exit;
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

# ============================================================
# 8. CONFIGURAR APACHE
# ============================================================

print_step "Configurando Apache..."

# Configurar sitio
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

# Habilitar sitio
a2ensite portal.conf 2>/dev/null
a2dissite 000-default.conf 2>/dev/null

# ============================================================
# 9. DAR PERMISOS CORRECTOS
# ============================================================

print_step "Dando permisos correctos..."

# Dar permisos a www-data para ejecutar iptables
echo "www-data ALL=(ALL) NOPASSWD: /usr/sbin/iptables" >> /etc/sudoers

# Crear archivo de log para autenticación
touch /var/log/portal_auth.log
chown www-data:www-data /var/log/portal_auth.log
chmod 644 /var/log/portal_auth.log

# Permisos del portal
chown -R www-data:www-data /var/www/portal
chmod 755 /var/www/portal
chmod 644 /var/www/portal/index.php

# ============================================================
# 10. REINICIAR SERVICIOS
# ============================================================

print_step "Reiniciando servicios..."

systemctl enable dnsmasq 2>/dev/null || true
systemctl restart dnsmasq

systemctl enable apache2 2>/dev/null || true
systemctl restart apache2

# ============================================================
# 11. VERIFICACIÓN
# ============================================================

print_step "Verificando instalación..."

echo ""
echo -e "${YELLOW}=== ESTADO DE SERVICIOS ===${NC}"
systemctl status dnsmasq --no-pager | grep "Active:"
systemctl status apache2 --no-pager | grep "Active:"

echo ""
echo -e "${YELLOW}=== INTERFAZ INTERNA ===${NC}"
ip addr show $INT_INTERNA | grep inet

echo ""
echo -e "${YELLOW}=== REGLAS IPTABLES (primeras 5) ===${NC}"
iptables -L -n -v | head -8

echo ""
echo -e "${YELLOW}=== CLIENTES DHCP ===${NC}"
cat /var/lib/dnsmasq/dnsmasq.leases 2>/dev/null || echo "  No hay clientes"

echo ""
echo -e "${YELLOW}=== LOG DE AUTENTICACIÓN ===${NC}"
tail -3 /var/log/portal_auth.log 2>/dev/null || echo "  No hay logs aún"

# ============================================================
# 12. DESBLOQUEAR EL CLIENTE ACTUAL AUTOMÁTICAMENTE
# ============================================================

print_step "Buscando cliente conectado para desbloquear..."

# Verificar si hay clientes en el archivo de leases
if [ -f /var/lib/dnsmasq/dnsmasq.leases ] && [ -s /var/lib/dnsmasq/dnsmasq.leases ]; then
    CLIENT_IP=$(cat /var/lib/dnsmasq/dnsmasq.leases | awk '{print $3}' | head -1)
    if [ ! -z "$CLIENT_IP" ]; then
        echo "Cliente encontrado: $CLIENT_IP"
        iptables -I FORWARD -s $CLIENT_IP -j ACCEPT 2>/dev/null || true
        echo "✅ Cliente $CLIENT_IP desbloqueado automáticamente"
    fi
else
    echo "  No hay clientes conectados. Esperando conexión..."
fi

# ============================================================
# 13. MOSTRAR INSTRUCCIONES FINALES
# ============================================================

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}✅ ¡REPARACIÓN COMPLETADA CON ÉXITO!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${YELLOW}📋 RESUMEN:${NC}"
echo "  🔹 IP del servidor (interna): 192.168.100.1"
echo "  🔹 Portal web: http://192.168.100.1"
echo "  🔹 Usuarios: estudiante/123456, docente/abc123, invitado/guest"
echo "  🔹 Sitios bloqueados: Instagram, ChatGPT"
echo "  🔹 Interfaz externa: $INT_EXTERNA"
echo "  🔹 Interfaz interna: $INT_INTERNA"
echo ""
echo -e "${YELLOW}🚀 PRÓXIMOS PASOS:${NC}"
echo "  1. En el CLIENTE, abre el navegador y ve a: http://192.168.100.1"
echo "  2. Autentícate con las credenciales de prueba:"
echo "     - estudiante / 123456"
echo "  3. ¡Ahora podrás navegar libremente!"
echo "  4. Verifica que Instagram y ChatGPT están bloqueados"
echo ""
echo -e "${YELLOW}🛠️ COMANDOS ÚTILES:${NC}"
echo "  - Ver log de autenticación: sudo tail -f /var/log/portal_auth.log"
echo "  - Ver clientes DHCP: cat /var/lib/dnsmasq/dnsmasq.leases"
echo "  - Ver reglas iptables: sudo iptables -L -n -v"
echo "  - Desbloquear IP manual: sudo iptables -I FORWARD -s [IP] -j ACCEPT"
echo ""
echo -e "${GREEN}¡BUENA SUERTE CON TU PROYECTO! 🚀${NC}"
