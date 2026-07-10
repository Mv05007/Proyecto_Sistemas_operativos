#!/bin/bash

# ============================================================
# PORTAL CAUTIVO - INSTALADOR DEFINITIVO
# ============================================================
# Autor: Mauro
# Descripción: Instala y configura portal cautivo con 
#              auto-corrección de errores
# ============================================================

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables globales
INT_EXTERNA=""
INT_INTERNA=""
ERROR_COUNT=0

# ============================================================
# FUNCIONES
# ============================================================

print_header() {
    clear
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║     PORTAL CAUTIVO - INSTALADOR DEFINITIVO v2.0         ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() { echo -e "\n${GREEN}▶ $1${NC}"; }
print_error() { echo -e "${RED}✘ ERROR: $1${NC}"; ((ERROR_COUNT++)); }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# ============================================================
# FUNCIÓN: Detectar interfaces automáticamente
# ============================================================

detect_interfaces() {
    print_step "Detectando interfaces de red automáticamente..."
    
    # Obtener todas las interfaces (excepto loopback)
    local interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo))
    
    echo "Interfaces disponibles:"
    for i in "${!interfaces[@]}"; do
        echo "  $((i+1))) ${interfaces[$i]}"
    done
    echo ""
    
    # Identificar interfaz EXTERNA (la que tiene Internet)
    for iface in "${interfaces[@]}"; do
        if ping -c 1 -I $iface 8.8.8.8 &>/dev/null 2>&1; then
            INT_EXTERNA=$iface
            print_success "Interfaz EXTERNA (con Internet): $INT_EXTERNA"
            break
        fi
    done
    
    # Si no se encontró automáticamente, preguntar
    if [ -z "$INT_EXTERNA" ]; then
        print_warning "No se pudo detectar automáticamente la interfaz externa"
        read -p "Interfaz EXTERNA (NAT/Internet) [ens33]: " INT_EXTERNA
        INT_EXTERNA=${INT_EXTERNA:-ens33}
    fi
    
    # Identificar interfaz INTERNA (la que NO tiene Internet)
    for iface in "${interfaces[@]}"; do
        if [ "$iface" != "$INT_EXTERNA" ]; then
            INT_INTERNA=$iface
            print_success "Interfaz INTERNA (red-interna): $INT_INTERNA"
            break
        fi
    done
    
    # Si no se encontró, preguntar
    if [ -z "$INT_INTERNA" ]; then
        print_warning "No se pudo detectar automáticamente la interfaz interna"
        read -p "Interfaz INTERNA (red-interna) [ens34]: " INT_INTERNA
        INT_INTERNA=${INT_INTERNA:-ens34}
    fi
    
    # Verificar que las interfaces existen
    if ! ip link show $INT_EXTERNA &> /dev/null; then
        print_error "La interfaz $INT_EXTERNA no existe"
        return 1
    fi
    
    if ! ip link show $INT_INTERNA &> /dev/null; then
        print_error "La interfaz $INT_INTERNA no existe"
        return 1
    fi
    
    print_success "Interfaces configuradas: EXTERNA=$INT_EXTERNA, INTERNA=$INT_INTERNA"
    return 0
}

# ============================================================
# FUNCIÓN: Verificar y corregir permisos de dnsmasq
# ============================================================

fix_dnsmasq_permissions() {
    print_step "Verificando permisos de dnsmasq..."
    
    # Crear directorio si no existe
    if [ ! -d "/var/lib/dnsmasq" ]; then
        print_warning "Directorio /var/lib/dnsmasq no existe. Creando..."
        sudo mkdir -p /var/lib/dnsmasq
    fi
    
    # Crear archivo de leases si no existe
    if [ ! -f "/var/lib/dnsmasq/dnsmasq.leases" ]; then
        print_warning "Archivo dnsmasq.leases no existe. Creando..."
        sudo touch /var/lib/dnsmasq/dnsmasq.leases
    fi
    
    # Detectar usuario de dnsmasq
    local DNSMASQ_USER=$(ps aux | grep -E "[d]nsmasq" | head -1 | awk '{print $1}')
    
    if [ -z "$DNSMASQ_USER" ]; then
        # Si no está corriendo, intentar obtener del archivo de configuración
        DNSMASQ_USER=$(grep -E "^user=" /etc/dnsmasq.conf 2>/dev/null | cut -d= -f2)
        [ -z "$DNSMASQ_USER" ] && DNSMASQ_USER="nobody"
    fi
    
    print_info "Usuario de dnsmasq: $DNSMASQ_USER"
    
    # Asignar permisos correctos
    sudo chown -R $DNSMASQ_USER:$DNSMASQ_USER /var/lib/dnsmasq 2>/dev/null || \
    sudo chown -R $DNSMASQ_USER:nogroup /var/lib/dnsmasq 2>/dev/null || \
    sudo chmod 666 /var/lib/dnsmasq/dnsmasq.leases
    
    sudo chmod 755 /var/lib/dnsmasq
    sudo chmod 644 /var/lib/dnsmasq/dnsmasq.leases
    
    print_success "Permisos de dnsmasq corregidos"
}

# ============================================================
# FUNCIÓN: Verificar y liberar puerto 53
# ============================================================

fix_port_53() {
    print_step "Verificando puerto 53..."
    
    # Verificar si el puerto 53 está en uso
    if sudo netstat -tulpn | grep -q ":53 "; then
        print_warning "Puerto 53 está en uso por otro servicio"
        
        # Detener systemd-resolved si está corriendo
        if systemctl is-active --quiet systemd-resolved; then
            print_info "Deteniendo systemd-resolved..."
            sudo systemctl stop systemd-resolved
            sudo systemctl disable systemd-resolved
        fi
        
        # Matar cualquier proceso en el puerto 53
        local pid=$(sudo lsof -t -i :53 2>/dev/null | head -1)
        if [ ! -z "$pid" ]; then
            print_info "Matando proceso $pid en el puerto 53..."
            sudo kill -9 $pid 2>/dev/null || true
        fi
        
        print_success "Puerto 53 liberado"
    else
        print_success "Puerto 53 disponible"
    fi
}

# ============================================================
# FUNCIÓN: Verificar y configurar interfaz interna
# ============================================================

fix_internal_interface() {
    print_step "Verificando interfaz interna..."
    
    # Activar interfaz
    sudo ip link set $INT_INTERNA up 2>/dev/null || true
    
    # Verificar si tiene IP
    local CURRENT_IP=$(ip -4 addr show $INT_INTERNA | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "")
    
    if [ "$CURRENT_IP" != "192.168.100.1" ]; then
        print_warning "Interfaz $INT_INTERNA no tiene IP 192.168.100.1"
        
        # Eliminar IPs existentes
        sudo ip addr flush dev $INT_INTERNA 2>/dev/null || true
        
        # Asignar IP
        sudo ip addr add 192.168.100.1/24 dev $INT_INTERNA
        print_success "IP 192.168.100.1 asignada a $INT_INTERNA"
    else
        print_success "Interfaz $INT_INTERNA ya tiene IP 192.168.100.1"
    fi
}

# ============================================================
# FUNCIÓN: Configurar dnsmasq con validación
# ============================================================

configure_dnsmasq() {
    print_step "Configurando dnsmasq..."
    
    # Respaldar configuración existente
    [ -f /etc/dnsmasq.conf ] && sudo cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # Crear configuración
    sudo cat > /etc/dnsmasq.conf << EOF
# ============================================================
# DNSMASQ - PORTAL CAUTIVO
# ============================================================

# Interfaz donde atenderá DHCP
interface=$INT_INTERNA

# No escuchar en la interfaz externa
no-dhcp-interface=$INT_EXTERNA

# Rango de IPs para clientes
dhcp-range=192.168.100.50,192.168.100.100,255.255.255.0,12h

# Gateway (el servidor)
dhcp-option=option:router,192.168.100.1

# DNS
dhcp-option=option:dns-server,8.8.8.8,1.1.1.1

# Tiempo de arrendamiento
dhcp-lease-max=50

# Archivo de leases
dhcp-leasefile=/var/lib/dnsmasq/dnsmasq.leases

# ============================================================
# BLOQUEO DE DOMINIOS
# ============================================================

# Instagram
address=/instagram.com/0.0.0.0
address=/www.instagram.com/0.0.0.0
address=/cdninstagram.com/0.0.0.0

# ChatGPT
address=/chatgpt.com/0.0.0.0
address=/www.chatgpt.com/0.0.0.0
address=/openai.com/0.0.0.0
address=/auth.openai.com/0.0.0.0

# Logging
log-queries
log-facility=/var/log/dnsmasq.log
EOF

    print_success "Configuración de dnsmasq creada"
}

# ============================================================
# FUNCIÓN: Configurar iptables con validación
# ============================================================

configure_iptables() {
    print_step "Configurando iptables..."
    
    # Limpiar reglas existentes (opcional)
    # sudo iptables -F
    # sudo iptables -t nat -F
    
    # 1. NAT (Masquerading)
    sudo iptables -t nat -A POSTROUTING -o $INT_EXTERNA -j MASQUERADE 2>/dev/null || true
    
    # 2. Permitir forwarding
    sudo iptables -A FORWARD -i $INT_INTERNA -o $INT_EXTERNA -j ACCEPT 2>/dev/null || true
    sudo iptables -A FORWARD -i $INT_EXTERNA -o $INT_INTERNA -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    
    # 3. Redirigir tráfico HTTP/HTTPS al portal
    sudo iptables -t nat -A PREROUTING -i $INT_INTERNA -p tcp --dport 80 -j DNAT --to-destination 192.168.100.1:80 2>/dev/null || true
    sudo iptables -t nat -A PREROUTING -i $INT_INTERNA -p tcp --dport 443 -j DNAT --to-destination 192.168.100.1:80 2>/dev/null || true
    
    # 4. Permitir DNS
    sudo iptables -I FORWARD -i $INT_INTERNA -p udp --dport 53 -j ACCEPT 2>/dev/null || true
    sudo iptables -I FORWARD -i $INT_INTERNA -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
    
    # 5. Bloquear Instagram y ChatGPT por IP
    sudo iptables -I FORWARD -d 157.240.0.0/16 -j DROP 2>/dev/null || true
    sudo iptables -I FORWARD -d 31.13.0.0/16 -j DROP 2>/dev/null || true
    sudo iptables -I FORWARD -d 34.120.0.0/16 -j DROP 2>/dev/null || true
    sudo iptables -I FORWARD -d 35.190.0.0/16 -j DROP 2>/dev/null || true
    
    # 6. Política por defecto DROP en FORWARD
    sudo iptables -P FORWARD DROP 2>/dev/null || true
    
    # 7. Permitir acceso al servidor web (portal)
    sudo iptables -I INPUT -i $INT_INTERNA -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
    sudo iptables -I INPUT -i $INT_INTERNA -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
    
    # Guardar reglas
    sudo netfilter-persistent save 2>/dev/null || true
    
    print_success "Iptables configurado"
}

# ============================================================
# FUNCIÓN: Configurar portal web
# ============================================================

configure_portal() {
    print_step "Configurando portal web..."
    
    # Crear directorio
    sudo mkdir -p /var/www/portal
    
    # Crear archivo PHP
    sudo cat > /var/www/portal/index.php << 'PHPEOF'
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

    # Configurar Apache
    sudo cat > /etc/apache2/sites-available/portal.conf << EOF
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
    sudo a2ensite portal.conf 2>/dev/null
    sudo a2dissite 000-default.conf 2>/dev/null
    
    # Dar permisos a www-data para ejecutar iptables
    echo "www-data ALL=(ALL) NOPASSWD: /usr/sbin/iptables" | sudo tee -a /etc/sudoers > /dev/null
    
    sudo systemctl restart apache2
    
    print_success "Portal web configurado"
}

# ============================================================
# FUNCIÓN: Iniciar servicios con verificación
# ============================================================

start_services() {
    print_step "Iniciando servicios..."
    
    # Habilitar y reiniciar dnsmasq
    sudo systemctl enable dnsmasq 2>/dev/null || true
    
    # Intentar iniciar dnsmasq varias veces
    local attempts=0
    local max_attempts=5
    
    while [ $attempts -lt $max_attempts ]; do
        sudo systemctl restart dnsmasq 2>/dev/null
        
        if systemctl is-active --quiet dnsmasq; then
            print_success "dnsmasq iniciado correctamente"
            break
        fi
        
        ((attempts++))
        print_warning "Intento $attempts de $max_attempts falló. Reintentando..."
        sleep 2
        
        # Intentar arreglar problemas comunes
        if [ $attempts -eq 1 ]; then
            fix_dnsmasq_permissions
        elif [ $attempts -eq 2 ]; then
            fix_port_53
        elif [ $attempts -eq 3 ]; then
            sudo rm -f /var/lib/dnsmasq/dnsmasq.leases
            sudo touch /var/lib/dnsmasq/dnsmasq.leases
            sudo chmod 666 /var/lib/dnsmasq/dnsmasq.leases
        fi
    done
    
    # Verificar estado final
    if systemctl is-active --quiet dnsmasq; then
        print_success "dnsmasq está activo"
    else
        print_error "No se pudo iniciar dnsmasq después de $max_attempts intentos"
        print_info "Ejecuta 'sudo journalctl -xeu dnsmasq.service' para ver más detalles"
    fi
    
    # Apache
    sudo systemctl enable apache2 2>/dev/null || true
    sudo systemctl restart apache2
    if systemctl is-active --quiet apache2; then
        print_success "Apache2 está activo"
    else
        print_error "Apache2 no pudo iniciar"
    fi
}

# ============================================================
# FUNCIÓN: Verificar todo
# ============================================================

verify_installation() {
    print_step "Verificando instalación..."
    
    echo ""
    echo -e "${YELLOW}=== RESUMEN DE CONFIGURACIÓN ===${NC}"
    echo "1. IP del servidor (interna): 192.168.100.1"
    echo "2. Rango DHCP: 192.168.100.50 - 192.168.100.100"
    echo "3. Portal web: http://192.168.100.1"
    echo "4. Usuarios: estudiante/123456, docente/abc123, invitado/guest"
    echo "5. Sitios bloqueados: Instagram, ChatGPT"
    echo "6. Interfaz externa: $INT_EXTERNA"
    echo "7. Interfaz interna: $INT_INTERNA"
    echo ""
    
    echo -e "${YELLOW}=== ESTADO DE SERVICIOS ===${NC}"
    systemctl status dnsmasq --no-pager | grep "Active:" || echo "⚠️ dnsmasq no está activo"
    systemctl status apache2 --no-pager | grep "Active:" || echo "⚠️ Apache2 no está activo"
    echo ""
    
    echo -e "${YELLOW}=== INTERFACES ===${NC}"
    ip -4 addr show $INT_INTERNA | grep inet || echo "⚠️ No se encontró IP en $INT_INTERNA"
    echo ""
    
    echo -e "${YELLOW}=== CLIENTES DHCP ===${NC}"
    if [ -f /var/lib/dnsmasq/dnsmasq.leases ]; then
        cat /var/lib/dnsmasq/dnsmasq.leases | while read line; do
            echo "  - $line"
        done
    else
        echo "  No hay clientes conectados"
    fi
    echo ""
    
    echo -e "${YELLOW}=== REGLAS IPTABLES (primeras 10) ===${NC}"
    sudo iptables -L -n -v | head -10
    echo ""
}

# ============================================================
# FUNCIÓN: Mostrar próximos pasos
# ============================================================

show_next_steps() {
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN} INSTALACIÓN COMPLETADA CON ÉXITO${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "${YELLOW} PRÓXIMOS PASOS:${NC}"
    echo "  1. En el CLIENTE (Ubuntu GUI), asegúrate de tener DHCP activado"
    echo "  2. Abre un navegador en el cliente y visita cualquier página"
    echo "  3. Serás redirigido automáticamente al portal: http://192.168.100.1"
    echo "  4. Autentícate con las credenciales de prueba:"
    echo "     - estudiante / 123456"
    echo "     - docente / abc123"
    echo "     - invitado / guest"
    echo "  5. Verifica que puedes navegar libremente"
    echo "  6. Prueba acceder a instagram.com y chatgpt.com (deben estar bloqueados)"
    echo ""
    echo -e "${YELLOW}🛠️ COMANDOS ÚTILES:${NC}"
    echo "  - Ver clientes DHCP: cat /var/lib/dnsmasq/dnsmasq.leases"
    echo "  - Ver reglas iptables: sudo iptables -L -n -v"
    echo "  - Reiniciar servicios: sudo systemctl restart dnsmasq apache2"
    echo "  - Ver logs: sudo tail -f /var/log/dnsmasq.log"
    echo ""
    echo -e "${GREEN}¡Buena suerte con tu proyecto! 🚀${NC}"
}

# ============================================================
# FUNCIÓN: Reintentar todo si falla
# ============================================================

retry_all() {
    print_warning "Algo falló. Reintentando configuración completa..."
    fix_internal_interface
    fix_port_53
    fix_dnsmasq_permissions
    configure_dnsmasq
    configure_iptables
    configure_portal
    start_services
}

# ============================================================
# MAIN
# ============================================================

main() {
    print_header
    
    # Verificar root
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script debe ejecutarse con sudo"
        exit 1
    fi
    
    # Detectar interfaces
    if ! detect_interfaces; then
        print_error "No se pudieron detectar las interfaces"
        exit 1
    fi
    
    # Instalar paquetes
    print_step "Instalando paquetes necesarios..."
    apt update -y
    apt install -y dnsmasq apache2 php iptables-persistent net-tools curl wget
    
    # Configurar todo
    fix_internal_interface
    fix_port_53
    fix_dnsmasq_permissions
    configure_dnsmasq
    configure_iptables
    configure_portal
    start_services
    
    # Verificar y reintentar si es necesario
    if ! systemctl is-active --quiet dnsmasq; then
        print_warning "dnsmasq no está activo. Reintentando..."
        retry_all
    fi
    
    # Mostrar resumen
    verify_installation
    show_next_steps
    
    # Guardar log de errores si los hubo
    if [ $ERROR_COUNT -gt 0 ]; then
        echo "⚠️ Se encontraron $ERROR_COUNT errores durante la instalación"
        echo "Revisa los mensajes de error arriba para más detalles"
    fi
}

# ============================================================
# EJECUTAR
# ============================================================

main "$@"
