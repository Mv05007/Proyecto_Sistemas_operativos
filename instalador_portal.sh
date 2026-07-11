#!/bin/bash

echo "=========================================================="
echo " INICIANDO INSTALACIÓN TOTAL DEL PORTAL CAUTIVO"
echo "=========================================================="

# --- 1. CREACIÓN DEL ARCHIVO PHP (indexx.php) ---
echo "[1/5] Generando el código de la página web..."

# Nota: El 'EOF' entre comillas simples evita que Bash confunda las variables de PHP
cat << 'EOF' > /var/www/html/indexx.php
<?php
$mensaje = "";
$exito = false;

if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $usuario = isset($_POST['usuario']) ? $_POST['usuario'] : '';
    $password = isset($_POST['password']) ? $_POST['password'] : '';

    if ($usuario === "estudiante" && $password === "123456") {
        $ip_cliente = $_SERVER['REMOTE_ADDR'];

        // Comando para abrir el firewall con captura de errores (2>&1)
        $comando = "sudo /usr/sbin/iptables -I FORWARD 1 -s " . escapeshellarg($ip_cliente) . " -j ACCEPT 2>&1";
        
        exec($comando, $output, $return_var);

        if ($return_var === 0) {
            $exito = true;
            $mensaje = "¡Autenticación exitosa! Disfruta tu navegación.";
        } else {
            $mensaje = "Error interno (Cód: $return_var): " . implode(" ", $output);
        }
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
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%); height: 100vh; display: flex; align-items: center; justify-content: center; margin: 0; }
        .card { background: white; padding: 40px; border-radius: 8px; box-shadow: 0 15px 30px rgba(0,0,0,0.3); text-align: center; width: 320px; }
        .success { background: #d4edda; color: #155724; padding: 10px; border-radius: 6px; margin-bottom: 15px; font-weight: bold; }
        .error { background: #f8d7da; color: #721c24; padding: 10px; border-radius: 6px; margin-bottom: 15px; font-size: 14px; }
        input { width: 90%; padding: 10px; margin-bottom: 15px; border: 1px solid #ccc; border-radius: 4px; }
        button { width: 100%; padding: 10px; background: #1e3c72; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 16px; }
        button:hover { background: #2a5298; }
    </style>
</head>
<body>
    <div class="card">
        <h2>Portal de Autenticación</h2>
        <?php if ($mensaje): ?>
            <div class="<?php echo $exito ? 'success' : 'error'; ?>"><?php echo $mensaje; ?></div>
        <?php endif; ?>
        
        <?php if (!$exito): ?>
        <form method="POST">
            <input type="text" name="usuario" placeholder="Usuario" required>
            <input type="password" name="password" placeholder="Contraseña" required>
            <button type="submit">Conectar</button>
        </form>
        <?php endif; ?>
    </div>
</body>
</html>
EOF

# --- 2. ENRUTAMIENTO Y NAT ---
echo "[2/5] Configurando enrutamiento del servidor..."
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t nat -A POSTROUTING -j MASQUERADE

# --- 3. EL CANDADO PRINCIPAL ---
echo "[3/5] Aplicando bloqueo general (DROP) a la red..."
sudo iptables -A FORWARD -s 192.168.50.0/24 -j DROP

# --- 4. PERMISOS DEL SISTEMA Y WEB ---
echo "[4/5] Configurando permisos sudoers y de Apache..."
echo "www-data ALL=(ALL) NOPASSWD: /usr/sbin/iptables" | sudo tee /etc/sudoers.d/99_www_data_iptables > /dev/null
sudo chmod 440 /etc/sudoers.d/99_www_data_iptables

sudo chown -R www-data:www-data /var/www/html/
sudo chmod 644 /var/www/html/indexx.php

# --- 5. REINICIO DE SERVICIOS ---
echo "[5/5] Reiniciando servidor web..."
sudo systemctl restart apache2

echo "=========================================================="
echo " ¡INSTALACIÓN COMPLETADA CON ÉXITO!"
echo " El archivo indexx.php fue creado y la red está protegida."
echo " Ve a tu máquina cliente y haz la prueba final."
echo "=========================================================="
