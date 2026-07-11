#!/bin/bash

echo "===================================================="
echo "🚀 INICIANDO DESPLIEGUE DEL PORTAL CAUTIVO..."
echo "===================================================="

# --- 0. Comprobación de permisos ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: Por favor, ejecuta este script con sudo."
  exit 1
fi

# Variables de red (Ajustadas a tu laboratorio)
IF_INTERNET="ens33"
RED_CLIENTES="192.168.50.0/24"
IP_SERVIDOR="192.168.50.1"

# --- 1. CONFIGURACIÓN DE RED Y CORTAFUEGOS (IPTABLES) ---
echo "✅ 1. Configurando enrutamiento y cortafuegos..."
# Activar IP Forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null

# Limpiar reglas anteriores para evitar duplicados
iptables -F FORWARD
iptables -t nat -F POSTROUTING

# Compartir internet (NAT)
iptables -t nat -A POSTROUTING -o $IF_INTERNET -j MASQUERADE

# Bloquear el tráfico de los clientes por defecto
iptables -A FORWARD -s $RED_CLIENTES -j DROP

# --- 2. PERMISOS DE APACHE ---
echo "✅ 2. Otorgando permisos a Apache..."
echo "www-data ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/portal-apache
chmod 0440 /etc/sudoers.d/portal-apache

# --- 3. CONFIGURACIÓN DEL DNS (DNSMASQ) ---
echo "✅ 3. Configurando secuestro de DNS..."
# Limpiamos configuraciones previas del portal en dnsmasq
sed -i '/neverssl.com/d' /etc/dnsmasq.conf
sed -i '/connectivity-check/d' /etc/dnsmasq.conf
sed -i '/no-resolv/d' /etc/dnsmasq.conf
sed -i '/server=8.8.8.8/d' /etc/dnsmasq.conf

# Inyectamos la configuración blindada
cat <<EOF >> /etc/dnsmasq.conf
no-resolv
server=8.8.8.8
address=/neverssl.com/$IP_SERVIDOR
address=/connectivity-check.ubuntu.com/$IP_SERVIDOR
EOF

# --- 4. CREACIÓN DEL PORTAL WEB (PHP) ---
echo "✅ 4. Generando portal web (index.php)..."
cat << 'EOF' > /var/www/html/index.php
<?php
$mensaje = "";
$exito = false;

if ($_SERVER["REQUEST_METHOD"] == "POST") {
    $usuario = $_POST['usuario'];
    $password = $_POST['password'];

    if ($usuario === "estudiante" && $password === "123456") {
        $ip_cliente = $_SERVER['REMOTE_ADDR'];
        
        // Ejecución en segundo plano para evitar cuelgues
        $comando = "sudo /usr/sbin/iptables -I FORWARD -s " . escapeshellarg($ip_cliente) . " -j ACCEPT > /dev/null 2>&1 &";
        exec($comando);

        $exito = true;
        $mensaje = "¡Autenticación exitosa!";
    } else {
        $mensaje = "Usuario o contraseña incorrectos.";
    }
}
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Portal Cautivo</title>
    <?php if ($exito): ?>
    <meta http-equiv="refresh" content="2;url=http://www.bing.com">
    <?php endif; ?>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%); height: 100vh; display: flex; align-items: center; justify-content: center; margin: 0; }
        .card { background: white; padding: 40px; border-radius: 12px; box-shadow: 0 15px 30px rgba(0,0,0,0.3); text-align: center; width: 320px; }
        h2 { color: #333; margin-top: 0; }
        input { width: 90%; padding: 12px; margin: 10px 0; border: 1px solid #ddd; border-radius: 6px; font-size: 14px; }
        button { background: #007bff; color: white; border: none; padding: 12px; border-radius: 6px; cursor: pointer; width: 100%; font-size: 16px; font-weight: bold; margin-top: 15px; transition: background 0.3s; }
        button:hover { background: #0056b3; }
        .success { background: #d4edda; color: #155724; padding: 10px; border-radius: 6px; font-weight: bold; margin-bottom: 15px; }
        .error { background: #f8d7da; color: #721c24; padding: 10px; border-radius: 6px; margin-bottom: 15px; }
    </style>
</head>
<body>
    <div class="card">
        <h2>Acceso a la Red</h2>
        <p style="color: #666; margin-bottom: 20px;">Por favor, identifícate.</p>

        <?php if ($exito): ?>
            <div class="success"><?php echo $mensaje; ?></div>
            <p>Redirigiendo a internet...</p>
        <?php else: ?>
            <?php if ($mensaje): ?>
                <div class="error"><?php echo $mensaje; ?></div>
            <?php endif; ?>
            <form method="POST">
                <input type="text" name="usuario" placeholder="Usuario (estudiante)" required autocomplete="off">
                <input type="password" name="password" placeholder="Contraseña (123456)" required>
                <button type="submit">Conectar</button>
            </form>
        <?php endif; ?>
    </div>
</body>
</html>
EOF

# Ajustar dueños del archivo web
chown www-data:www-data /var/www/html/index.php

# --- 5. REINICIO DE SERVICIOS ---
echo "✅ 5. Reiniciando servicios (Apache y DNS)..."
systemctl restart apache2
systemctl restart dnsmasq

echo "===================================================="
echo "🎉 ¡DESPLIEGUE COMPLETADO CON ÉXITO!"
echo "El servidor está listo para interceptar conexiones."
echo "===================================================="
