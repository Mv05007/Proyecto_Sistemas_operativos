#!/bin/bash
# ============================================================================
# PORTAL CAUTIVO CON BLOQUEO DE INSTAGRAM Y CHATGPT
# Script maestro - Ejecutar como: sudo bash portal.sh
# ============================================================================

set -e  # Detener si hay error grave

echo "==========================================================="
echo "  PORTAL CAUTIVO - INSTALACIÓN COMPLETA"
echo "==========================================================="

# --- 1. Variables de red (ajustar si tu interfaz no es ens33) ---
INTERFAZ="ens33"
SUBRED="192.168.50.0/24"
IP_SERVIDOR="192.168.50.1"
USUARIO_VALIDO="estudiante"
PASS_VALIDO="123456"

# --- 2. Activar enrutamiento ---
echo "[1/6] Activando enrutamiento IP..."
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# --- 3. Limpiar todas las reglas de iptables (nat y filter) ---
echo "[2/6] Limpiando reglas de iptables..."
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X
iptables -t nat -X
iptables -t mangle -X

# --- 4. Establecer políticas por defecto (seguras) ---
iptables -P INPUT ACCEPT
iptables -P FORWARD DROP   # Denegar todo el reenvío por defecto
iptables -P OUTPUT ACCEPT

# --- 5. Reglas de bloqueo de dominios prohibidos (SIEMPRE activas) ---
echo "[3/6] Aplicando bloqueo de Instagram y ChatGPT..."
iptables -I FORWARD 1 -m string --string "instagram.com" --algo bm --to 65535 -j REJECT
iptables -I FORWARD 2 -m string --string "chatgpt.com" --algo bm --to 65535 -j REJECT
iptables -I FORWARD 3 -m string --string "openai.com" --algo bm --to 65535 -j REJECT

# --- 6. Redirección HTTP al portal (para forzar login) ---
echo "[4/6] Configurando redirección HTTP al portal..."
iptables -t nat -A PREROUTING -i $INTERFAZ -p tcp --dport 80 -j DNAT --to-destination $IP_SERVIDOR:80
# Asegurar que el tráfico hacia el propio servidor no se redirija (loopback)
iptables -t nat -A OUTPUT -p tcp --dport 80 -d $IP_SERVIDOR -j ACCEPT

# --- 7. Regla DROP para toda la subred (los no autenticados) ---
# Esta regla estará al final de la cadena FORWARD, después de las reglas de aceptación dinámicas.
iptables -A FORWARD -s $SUBRED -j DROP

# --- 8. NAT (MASQUERADE) para salida a Internet ---
echo "[5/6] Configurando NAT..."
iptables -t nat -A POSTROUTING -j MASQUERADE

# --- 9. Crear el script "portero" que autoriza IPs ---
echo "[6/6] Instalando script portero y página web..."
cat > /usr/local/bin/portero.sh << 'EOF'
#!/bin/bash
# Recibe una IP y la autoriza en el firewall (posición 4, justo antes del DROP)
# Uso: portero.sh <IP>
if [ -z "$1" ]; then
    echo "Uso: portero.sh IP"
    exit 1
fi
# Insertar regla ACCEPT para esa IP en la posición 4 (después de los bloqueos)
/usr/sbin/iptables -I FORWARD 4 -s "$1" -j ACCEPT 2>/dev/null
# También permitir la respuesta (ESTABLISHED,RELATED) ya está permitida por defecto
exit 0
EOF

chmod +x /usr/local/bin/portero.sh

# --- 10. Configurar sudoers para que www-data ejecute el portero sin contraseña ---
echo "www-data ALL=(ALL) NOPASSWD: /usr/local/bin/portero.sh" > /etc/sudoers.d/99_www_data_iptables
chmod 440 /etc/sudoers.d/99_www_data_iptables

# --- 11. Crear la página web indexx.php ---
cat > /var/www/html/indexx.php << 'EOF'
<?php
if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $user = $_POST['usuario'] ?? '';
    $pass = $_POST['password'] ?? '';
    $usuario_valido = 'estudiante';
    $pass_valido = '123456';

    if ($user === $usuario_valido && $pass === $pass_valido) {
        $ip = $_SERVER['REMOTE_ADDR'];
        // Ejecutar el portero con la IP del cliente
        exec("sudo /usr/local/bin/portero.sh " . escapeshellarg($ip) . " 2>&1", $out, $ret);
        if ($ret === 0) {
            echo "<div style='background:#d4edda; color:#155724; padding:20px; text-align:center; font-family:sans-serif;'><h2>¡Autenticación exitosa!</h2><p>Redirigiendo a Bing...</p><meta http-equiv='refresh' content='2;url=http://www.bing.com'></div>";
            exit;
        } else {
            $errorMsg = implode(" ", $out);
            echo "<div style='background:#f8d7da; color:#721c24; padding:20px; text-align:center; font-family:sans-serif;'>Error del sistema: $errorMsg</div>";
        }
    } else {
        echo "<div style='background:#f8d7da; color:#721c24; padding:20px; text-align:center; font-family:sans-serif;'>Usuario o contraseña incorrectos.</div>";
    }
    exit;
}
?>
<!DOCTYPE html>
<html>
<head><title>Portal Cautivo</title></head>
<body style='background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%); display:flex; justify-content:center; align-items:center; height:100vh; margin:0; font-family:sans-serif;'>
<div style='background:white; padding:40px; border-radius:8px; text-align:center; width:300px; box-shadow: 0 10px 25px rgba(0,0,0,0.5);'>
    <h2>Portal Cautivo</h2>
    <p style='color:red; font-size:12px;'>* Instagram y ChatGPT están bloqueados</p>
    <form method='POST'>
        <input type='text' name='usuario' placeholder='Usuario' style='width:90%; padding:10px; margin-bottom:15px; border:1px solid #ccc; border-radius:4px;' required><br>
        <input type='password' name='password' placeholder='Contraseña' style='width:90%; padding:10px; margin-bottom:20px; border:1px solid #ccc; border-radius:4px;' required><br>
        <button type='submit' style='width:100%; background:#1e3c72; color:white; padding:10px; border:none; border-radius:4px; cursor:pointer;'>Conectar</button>
    </form>
</div>
</body>
</html>
EOF

chown www-data:www-data /var/www/html/indexx.php
chmod 644 /var/www/html/indexx.php

# --- 12. Reiniciar Apache ---
systemctl restart apache2

# --- 13. Mostrar estado final ---
echo ""
echo "==========================================================="
echo "  INSTALACIÓN COMPLETA"
echo "==========================================================="
echo "Reglas de FORWARD actuales:"
iptables -L FORWARD -n -v --line-numbers
echo ""
echo "Prueba desde el cliente: http://$IP_SERVIDOR/indexx.php"
echo "Usuario: $USUARIO_VALIDO   Contraseña: $PASS_VALIDO"
echo "==========================================================="
