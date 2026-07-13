#!/bin/bash
echo "=== Instalando Servidor Portal Cautivo Avanzado ==="

# 1. Limpieza total y Enrutamiento 
sysctl -w net.ipv4.ip_forward=1
iptables -F
iptables -t nat -F
iptables -t nat -A POSTROUTING -j MASQUERADE

# 2. LA LISTA NEGRA (Posiciones 1, 2 y 3)
# Bloqueo total de redes sociales e IA mediante inspección profunda de paquetes
iptables -A FORWARD -m string --string "instagram.com" --algo bm --to 65535 -j REJECT
iptables -A FORWARD -m string --string "chatgpt.com" --algo bm --to 65535 -j REJECT
iptables -A FORWARD -m string --string "openai.com" --algo bm --to 65535 -j REJECT

# 3. EL CANDADO GENERAL (Posición 4 por ahora)
iptables -A FORWARD -s 192.168.50.0/24 -j DROP

# 4. CREAR LA PÁGINA WEB CON EL NUEVO ORDEN DE REGLAS
cat << 'EOF' > /var/www/html/indexx.php
<?php
if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $user = $_POST['usuario'] ?? '';
    $pass = $_POST['password'] ?? '';
    
    if ($user === 'estudiante' && $pass === '123456') {
        $ip = $_SERVER['REMOTE_ADDR'];
        
        // ¡Magia aquí! Insertamos el permiso en la POSICIÓN 4. 
        // Así las reglas de bloqueo (1,2,3) siempre quedan arriba y funcionan incluso autenticado.
        $comando = "/usr/sbin/iptables -I FORWARD 4 -s " . escapeshellarg($ip) . " -j ACCEPT 2>&1";
        exec("sudo " . $comando, $out, $ret);
        
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
}
?>
<!DOCTYPE html>
<html>
<head><title>Portal Cautivo Seguro</title></head>
<body style='background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%); display:flex; justify-content:center; align-items:center; height:100vh; margin:0; font-family:sans-serif;'>
    <div style='background:white; padding:40px; border-radius:8px; text-align:center; width:300px; box-shadow: 0 10px 25px rgba(0,0,0,0.5);'>
        <h2>Portal Cautivo</h2>
        <p style='color:red; font-size:12px;'>* ChatGPT e Instagram restringidos en esta red.</p>
        <form method='POST'>
            <input type='text' name='usuario' placeholder='Usuario' style='width:90%; padding:10px; margin-bottom:15px; border:1px solid #ccc; border-radius:4px;' required><br>
            <input type='password' name='password' placeholder='Contraseña' style='width:90%; padding:10px; margin-bottom:20px; border:1px solid #ccc; border-radius:4px;' required><br>
            <button type='submit' style='width:100%; background:#1e3c72; color:white; padding:10px; border:none; border-radius:4px; cursor:pointer;'>Conectar</button>
        </form>
    </div>
</body>
</html>
EOF

# 5. PERMISOS DE APACHE Y SUDOERS
chown www-data:www-data /var/www/html/indexx.php
chmod 644 /var/www/html/indexx.php

echo "www-data ALL=(ALL) NOPASSWD: /usr/sbin/iptables" > /etc/sudoers.d/99_www_data_iptables
chmod 440 /etc/sudoers.d/99_www_data_iptables

# 6. REINICIO DEL SERVIDOR WEB
systemctl restart apache2

echo "=== ¡Despliegue finalizado con éxito! ==="
