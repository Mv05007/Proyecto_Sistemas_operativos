<?php
$mensaje = "";
$exito = false;

if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $usuario = isset($_POST['usuario']) ? $_POST['usuario'] : '';
    $password = isset($_POST['password']) ? $_POST['password'] : '';

    if ($usuario === "estudiante" && $password === "123456") {
        $ip_cliente = $_SERVER['REMOTE_ADDR'];
        
        // Comando con ruta absoluta y permisos sudo configurados
        $comando = "sudo /usr/sbin/iptables -I FORWARD 1 -s " . escapeshellarg($ip_cliente) . " -j ACCEPT";
        
        // Ejecución del comando
        exec($comando, $output, $return_var);

        if ($return_var === 0) {
            $exito = true;
            $mensaje = "¡Autenticación exitosa!";
        } else {
            $mensaje = "Error al aplicar reglas de red (Código: $return_var).";
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
        .success { background: #d4edda; color: #155724; padding: 10px; border-radius: 6px; margin-bottom: 10px; }
        .error { background: #f8d7da; color: #721c24; padding: 10px; border-radius: 6px; margin-bottom: 10px; }
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
            <input type="text" name="usuario" placeholder="Usuario" required><br><br>
            <input type="password" name="password" placeholder="Contraseña" required><br><br>
            <button type="submit">Conectar</button>
        </form>
        <?php endif; ?>
    </div>
</body>
</html>
