<?php
if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $user = $_POST['usuario'] ?? '';
    $pass = $_POST['password'] ?? '';
    if ($user === 'estudiante' && $pass === '123456') {
        $ip = $_SERVER['REMOTE_ADDR'];
        // Añadir regla ACCEPT para esa IP (con sudo sin contraseña)
        exec("sudo /sbin/iptables -I FORWARD -s $ip -j ACCEPT 2>&1", $out, $ret);
        if ($ret === 0) {
            echo "<div style='background:#d4edda; color:#155724; padding:20px;'><h2>¡Bienvenido!</h2><p>Redirigiendo...</p><meta http-equiv='refresh' content='2;url=http://www.bing.com'></div>";
            exit;
        } else {
            echo "<div style='background:#f8d7da; color:#721c24; padding:20px;'>Error: " . implode(" ", $out) . "</div>";
        }
    } else {
        echo "<div style='background:#f8d7da; color:#721c24; padding:20px;'>Usuario o contraseña incorrectos.</div>";
    }
}
?>
<!DOCTYPE html>
<html>
<head><title>Portal Cautivo</title></head>
<body style="font-family:sans-serif;background:#1e3c72;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;">
<div style="background:white;padding:40px;border-radius:8px;text-align:center;width:300px;">
    <h2>Acceso a Internet</h2>
    <p style="font-size:13px;color:red;">* Instagram y ChatGPT bloqueados</p>
    <form method="POST">
        <input type="text" name="usuario" placeholder="Usuario" style="width:90%;padding:10px;margin-bottom:10px;" required><br>
        <input type="password" name="password" placeholder="Contraseña" style="width:90%;padding:10px;margin-bottom:20px;" required><br>
        <button type="submit" style="background:#1e3c72;color:white;padding:10px 20px;border:none;border-radius:4px;cursor:pointer;">Conectar</button>
    </form>
</div>
</body>
</html>
