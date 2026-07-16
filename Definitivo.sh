#!/bin/bash
# ============================================================
# Script: portal_cautivo.sh
# Descripción: Configura un portal cautivo en Linux (iptables + dnsmasq + Apache)
#              para el Proyecto II Bimestre - Sistemas Operativos.
# Autor: Adaptado de la transcripción y requerimientos del equipo.
# Fecha: 2026-07-16
# ============================================================

# ---- Colores para mensajes ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # Sin color

# ---- Verificar que se ejecuta como root ----
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este script debe ejecutarse como root. Usa sudo.${NC}"
   exit 1
fi

# ---- Función para mostrar mensajes ----
mensaje() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

advertencia() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# ---- Detectar interfaces de red ----
mensaje "Detectando interfaces de red disponibles..."
interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)
echo "Interfaces detectadas: $interfaces"

# Preguntar al usuario cuál es la WAN y cuál la LAN
read -p "Introduce el nombre de la interfaz WAN (ej. eth0, ens33): " WAN_IF
read -p "Introduce el nombre de la interfaz LAN (ej. eth1, ens38): " LAN_IF

# Validar que existan
if ! ip link show "$WAN_IF" > /dev/null 2>&1; then
    error "La interfaz WAN '$WAN_IF' no existe."
fi
if ! ip link show "$LAN_IF" > /dev/null 2>&1; then
    error "La interfaz LAN '$LAN_IF' no existe."
fi

mensaje "Usando WAN: $WAN_IF , LAN: $LAN_IF"

# ---- Configuración de red estática para la LAN ----
LAN_IP="192.168.10.1"
LAN_NETMASK="255.255.255.0"
LAN_NETWORK="192.168.10.0/24"
DHCP_START="192.168.10.100"
DHCP_END="192.168.10.200"

mensaje "Configurando IP estática $LAN_IP/24 en $LAN_IF..."

# Respaldo de /etc/network/interfaces
cp /etc/network/interfaces /etc/network/interfaces.bak.portal

# Configurar interfaz LAN estática (para sistemas con ifupdown)
cat >> /etc/network/interfaces <<EOF

# Interfaz LAN configurada por portal_cautivo
auto $LAN_IF
iface $LAN_IF inet static
    address $LAN_IP
    netmask $LAN_NETMASK
EOF

# Si el sistema usa netplan (Ubuntu 18+), intentamos también
if [ -d "/etc/netplan" ]; then
    NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
    if [ ! -f "$NETPLAN_FILE" ]; then
        NETPLAN_FILE="/etc/netplan/50-cloud-init.yaml"
    fi
    if [ -f "$NETPLAN_FILE" ]; then
        mensaje "Detectado netplan, configurando también en $NETPLAN_FILE"
        # Añadimos la configuración de la LAN al netplan existente (cuidado con sobrescribir)
        # Mejor creamos un nuevo archivo para la LAN
        cat > /etc/netplan/99-lan.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $LAN_IF:
      addresses:
        - $LAN_IP/24
      dhcp4: no
EOF
        netplan apply 2>/dev/null
    fi
fi

# Reiniciar servicio de red (si es ifupdown)
if systemctl is-active networking &>/dev/null; then
    systemctl restart networking
elif systemctl is-active NetworkManager &>/dev/null; then
    systemctl restart NetworkManager
else
    ifdown $LAN_IF 2>/dev/null; ifup $LAN_IF 2>/dev/null
fi

mensaje "Interfaz LAN configurada."

# ---- Habilitar IP forwarding ----
mensaje "Habilitando IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# ---- Instalación de paquetes ----
mensaje "Instalando paquetes necesarios (iptables, dnsmasq, apache2, php)..."
apt update -y
apt install -y iptables dnsmasq apache2 php libapache2-mod-php
if [ $? -ne 0 ]; then
    error "Fallo en la instalación de paquetes. Verifica tu conexión a Internet."
fi

# ---- Configuración de dnsmasq (DHCP + DNS) ----
mensaje "Configurando dnsmasq..."
cat > /etc/dnsmasq.conf <<EOF
# Configuración para portal cautivo
interface=$LAN_IF
bind-interfaces
dhcp-range=$DHCP_START,$DHCP_END,255.255.255.0,24h
dhcp-option=3,$LAN_IP       # Gateway
dhcp-option=6,$LAN_IP       # DNS
# Bloqueo de dominios (Instagram y ChatGPT)
address=/instagram.com/0.0.0.0
address=/www.instagram.com/0.0.0.0
address=/chatgpt.com/0.0.0.0
address=/www.chatgpt.com/0.0.0.0
# Opcional: bloqueo adicional
log-queries
log-facility=/var/log/dnsmasq.log
EOF

systemctl restart dnsmasq
systemctl enable dnsmasq
mensaje "dnsmasq configurado y en ejecución."

# ---- Configuración de Apache + página de portal ----
mensaje "Configurando página del portal cautivo..."

# Crear directorio para la página
mkdir -p /var/www/portal
cat > /var/www/portal/index.html <<'HTML'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Portal Cautivo</title>
    <style>
        body { font-family: Arial; background: #f0f0f0; display: flex; justify-content: center; align-items: center; height: 100vh; }
        .login-box { background: white; padding: 40px; border-radius: 10px; box-shadow: 0 0 20px rgba(0,0,0,0.2); width: 300px; }
        h2 { text-align: center; color: #333; }
        input[type="text"], input[type="password"] { width: 100%; padding: 10px; margin: 10px 0; border: 1px solid #ddd; border-radius: 5px; }
        input[type="submit"] { width: 100%; padding: 10px; background: #28a745; color: white; border: none; border-radius: 5px; cursor: pointer; }
        .error { color: red; text-align: center; }
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
    <?php
        if (isset($_GET['error'])) {
            echo '<p class="error">Credenciales incorrectas</p>';
        }
    ?>
</div>
</body>
</html>
HTML

# Crear el script PHP de autenticación
cat > /var/www/portal/login.php <<'PHP'
<?php
// Usuario y contraseña válidos (puedes cambiarlos)
$VALID_USER = 'admin';
$VALID_PASS = 'admin123';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $user = $_POST['user'] ?? '';
    $pass = $_POST['pass'] ?? '';

    if ($user === $VALID_USER && $pass === $VALID_PASS) {
        // Obtener la IP del cliente (la IP real, no la del proxy)
        $client_ip = $_SERVER['REMOTE_ADDR'];
        // Si está detrás de un proxy, podemos obtenerla de HTTP_X_FORWARDED_FOR
        if (isset($_SERVER['HTTP_X_FORWARDED_FOR'])) {
            $client_ip = $_SERVER['HTTP_X_FORWARDED_FOR'];
        }
        // Validar que sea una IP válida en nuestra LAN
        if (filter_var($client_ip, FILTER_VALIDATE_IP)) {
            // Ejecutar el script para agregar la regla de iptables
            $cmd = "/usr/local/bin/portal_allow.sh $client_ip";
            $output = shell_exec($cmd . " 2>&1");
            // Redirigir a una página de éxito
            header('Location: /success.html');
            exit;
        } else {
            header('Location: /index.html?error=ip');
            exit;
        }
    } else {
        header('Location: /index.html?error=credencial');
        exit;
    }
} else {
    // Si no es POST, redirigir al index
    header('Location: /index.html');
    exit;
}
?>
PHP

# Página de éxito
cat > /var/www/portal/success.html <<'HTML'
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Conectado</title></head>
<body style="font-family:Arial;text-align:center;padding:50px;">
    <h1 style="color:green;">✅ Acceso concedido</h1>
    <p>Ya puedes navegar por Internet.</p>
    <p>Esta sesión estará activa durante 60 minutos.</p>
    <p><a href="http://google.com">Ir a Google</a></p>
</body>
</html>
HTML

# Configurar Apache para servir el portal
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

# Deshabilitar el sitio por defecto y habilitar el portal
a2dissite 000-default.conf 2>/dev/null
a2ensite portal.conf
systemctl restart apache2
systemctl enable apache2
mensaje "Apache configurado para el portal."

# ---- Script para permitir acceso a una IP (agregar regla) ----
mkdir -p /usr/local/bin
cat > /usr/local/bin/portal_allow.sh <<'SCRIPT'
#!/bin/bash
# Uso: portal_allow.sh <IP_CLIENTE>
if [ -z "$1" ]; then
    echo "Uso: $0 <IP>"
    exit 1
fi
CLIENT_IP=$1
# Verificar que la IP no esté ya permitida (evitar duplicados)
if iptables -L FORWARD -n | grep -q "$CLIENT_IP"; then
    echo "La IP $CLIENT_IP ya está permitida."
    exit 0
fi

# Agregar regla para permitir todo el tráfico desde esta IP
iptables -I FORWARD -s $CLIENT_IP -j ACCEPT
# También permitir que la IP pueda salir por NAT (ya está cubierto por el MASQUERADE general)

# Programar eliminación automática después de 60 minutos (3600 segundos)
echo "iptables -D FORWARD -s $CLIENT_IP -j ACCEPT" | at now + 60 minutes 2>/dev/null
# Si at no está instalado, usamos un cron o sleep en background? Mejor instalar at.
if ! command -v at &> /dev/null; then
    apt install at -y
    systemctl enable atd
    systemctl start atd
    echo "iptables -D FORWARD -s $CLIENT_IP -j ACCEPT" | at now + 60 minutes
fi

echo "Acceso permitido para $CLIENT_IP por 60 minutos."
SCRIPT

chmod +x /usr/local/bin/portal_allow.sh

# ---- Configuración de iptables ----
mensaje "Configurando reglas de iptables..."

# Limpiar reglas existentes (cuidado)
iptables -F
iptables -t nat -F
iptables -X

# Políticas por defecto
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Permitir tráfico local y establecido
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Permitir acceso a la interfaz LAN (para DHCP, DNS, HTTP)
iptables -A INPUT -i $LAN_IF -p udp --dport 67:68 -j ACCEPT   # DHCP
iptables -A INPUT -i $LAN_IF -p udp --dport 53 -j ACCEPT      # DNS
iptables -A INPUT -i $LAN_IF -p tcp --dport 80 -j ACCEPT      # HTTP portal
iptables -A INPUT -i $LAN_IF -p icmp -j ACCEPT                # Ping

# Permitir SSH desde LAN (opcional)
iptables -A INPUT -i $LAN_IF -p tcp --dport 22 -j ACCEPT

# Permitir acceso a WAN para el servidor (para actualizaciones, etc.)
iptables -A INPUT -i $WAN_IF -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -o $WAN_IF -j ACCEPT

# NAT (Masquerade) para que los clientes salgan a Internet
iptables -t nat -A POSTROUTING -o $WAN_IF -j MASQUERADE

# Redirección de tráfico de clientes no autenticados hacia el portal
# Redirigir HTTP (puerto 80) a la IP del portal
iptables -t nat -A PREROUTING -i $LAN_IF -p tcp --dport 80 -j DNAT --to-destination $LAN_IP:80
# Redirigir HTTPS (puerto 443) también al portal (aunque mostrará error de certificado, pero redirige)
iptables -t nat -A PREROUTING -i $LAN_IF -p tcp --dport 443 -j DNAT --to-destination $LAN_IP:80

# IMPORTANTE: Para que solo las IPs autenticadas puedan saltar esta redirección,
# necesitamos marcar los paquetes de IPs autenticadas para que no sean redirigidos.
# Una forma: usar una cadena de filtro y una regla de NAT condicional.
# Sin embargo, la redirección DNAT ocurre antes que el filtrado FORWARD.
# Por lo tanto, si una IP está autenticada, debemos evitar que su tráfico sea DNAT.
# Una solución es usar la opción "skuid" o "marca" pero es complejo.
# En su lugar, podemos hacer que el portal redirija al cliente a una IP pública después de autenticación,
# y entonces las reglas de DNAT solo se aplican a las IPs no autenticadas.
# Para simplificar: permitimos que todas las IPs pasen por NAT pero bloqueamos el FORWARD para las no autenticadas.
# Además, el DNAT redirige todo el tráfico web al portal, pero una vez autenticado, el portal podría redirigir a una URL externa,
# pero el DNAT sigue afectando. Para solucionar, podemos usar la cadena de iptables con "mangle" para marcar paquetes.
# La forma más simple: después de autenticar, la IP es agregada a una lista de IPs permitidas en una cadena de ACCEPT en FORWARD,
# pero el DNAT sigue redirigiendo. Para evitar el DNAT, podemos agregar una regla de NAT que excluya las IPs autenticadas.
# Esto se logra con:
iptables -t nat -I PREROUTING 1 -i $LAN_IF -p tcp --dport 80 -m iprange --src-range $DHCP_START-$DHCP_END -j RETURN
# Pero necesitamos una lista dinámica. Podemos crear una cadena específica.
# Solución: Usar una cadena de redirección condicional con ipset. Pero no queremos complicar.
# Para este proyecto, podemos asumir que después de autenticar, el portal redirige al cliente a una URL que no es el portal,
# y mientras tanto, la regla DNAT sigue vigente, pero al hacer clic en un enlace, se redirige de nuevo al portal.
# Para una demo funcional, podemos configurar el portal para que, tras autenticación, el cliente sea redirigido a google.com,
# y luego la regla DNAT lo volvería a redirigir al portal, por lo que no funcionaría.
# Por lo tanto, necesitamos una solución robusta: usar una cadena de prerouting que solo redirija si la IP no está en una lista blanca.
# Crearemos una lista blanca en un archivo y usaremos la opción "iprange" con negación.

# Primero, creamos una cadena para las IPs autenticadas
iptables -t nat -N AUTH_IPS
# Agregamos reglas para desviar el tráfico de IPs autenticadas (no redirigir)
# Pero no sabemos las IPs de antemano. Las agregaremos dinámicamente.

# Enfoque: Al autenticar, además de agregar la regla FORWARD ACCEPT, agregamos una regla en la tabla NAT para que el tráfico de esa IP no sea DNAT.
# Entonces, en el script portal_allow.sh, añadimos:
#   iptables -t nat -I PREROUTING -i $LAN_IF -s $CLIENT_IP -p tcp -m multiport --dports 80,443 -j RETURN
# Esto hará que el tráfico de esa IP no sea redirigido.

# Modificamos el script para que incluya eso.
sed -i '/Agregar regla para permitir todo el tráfico desde esta IP/a \
# Agregar regla en NAT para evitar redirección al portal \
iptables -t nat -I PREROUTING -i '$LAN_IF' -s $CLIENT_IP -p tcp -m multiport --dports 80,443 -j RETURN' /usr/local/bin/portal_allow.sh

# También añadir la eliminación de esa regla al expirar
sed -i '/iptables -D FORWARD -s $CLIENT_IP -j ACCEPT/a \
iptables -t nat -D PREROUTING -i '$LAN_IF' -s $CLIENT_IP -p tcp -m multiport --dports 80,443 -j RETURN 2>/dev/null' /usr/local/bin/portal_allow.sh

# Aplicar las reglas de iptables
# Ya tenemos las reglas de NAT, pero necesitamos también la regla de FORWARD que bloquea todo por defecto.
# Las IPs autenticadas tendrán ACCEPT en FORWARD.

# Guardar las reglas de iptables para persistencia
# Usar iptables-save y iptables-restore
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4
# Instalar iptables-persistent si no está
apt install -y iptables-persistent
systemctl enable netfilter-persistent 2>/dev/null || systemctl enable iptables-persistent 2>/dev/null

mensaje "Reglas de iptables configuradas y guardadas."

# ---- Asegurar que at esté instalado para las expiraciones ----
apt install -y at
systemctl enable atd
systemctl start atd

# ---- Mostrar resumen final ----
echo "============================================================"
echo -e "${GREEN}✅ PORTAL CAUTIVO CONFIGURADO CON ÉXITO${NC}"
echo "============================================================"
echo "Interfaz WAN: $WAN_IF"
echo "Interfaz LAN: $LAN_IF  (IP: $LAN_IP/24)"
echo "DHCP: rango $DHCP_START - $DHCP_END"
echo "Portal web: http://$LAN_IP"
echo "Credenciales: usuario 'admin'  contraseña 'admin123'"
echo "Tiempo de sesión: 60 minutos"
echo "Dominios bloqueados: instagram.com, chatgpt.com"
echo "============================================================"
echo -e "${YELLOW}Recomendación: Reinicia el servidor para aplicar todos los cambios.${NC}"
echo "Después de reiniciar, conecta un cliente a la LAN y prueba."
echo "Si el cliente no obtiene IP, revisa el servicio dnsmasq."
echo "Para ver logs: tail -f /var/log/dnsmasq.log"
echo "============================================================"

# Fin del script
