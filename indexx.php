<?php
if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $user = $_POST['usuario'] ?? '';
    $pass = $_POST['password'] ?? '';
    
    if ($user === 'estudiante' && $pass === '123456') {
        $ip = $_SERVER['REMOTE_ADDR'];
        exec("sudo /usr/sbin/iptables -I FORWARD 1 -s $ip -j ACCEPT 2>&1", $out, $ret);
        
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
<body style='background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%); display:flex; justify-content:center; align-items:center; height:100vh; margin:0; font-family:sans-serif;'>
    <div style='background:white; padding:40px; border-radius:8px; text-align:center; width:300px; box-shadow: 0 10px 25px rgba(0,0,0,0.5);'>
        <h2>Portal Cautivo</h2>
        <form method='POST'>
            <input type='text' name='usuario' placeholder='Usuario' style='width:90%; padding:10px; margin-bottom:15px; border:1px solid #ccc; border-radius:4px;' required><br>
            <input type='password' name='password' placeholder='Contraseña' style='width:90%; padding:10px; margin-bottom:20px; border:1px solid #ccc; border-radius:4px;' required><br>
            <button type='submit' style='width:100%; background:#1e3c72; color:white; padding:10px; border:none; border-radius:4px; cursor:pointer;'>Conectar</button>
        </form>
    </div>
</body>
</html>
