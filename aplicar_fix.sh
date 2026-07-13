#!/bin/bash
echo "Aplicando el FIX del Portero..."

# 1. Instalar el script portero
chmod +x portero.sh
cp portero.sh /usr/local/bin/portero.sh

# 2. Arreglar el sudoers (Añadimos !requiretty para evitar bloqueos ciegos)
echo -e "Defaults:www-data !requiretty\nwww-data ALL=(ALL) NOPASSWD: /usr/local/bin/portero.sh" > /etc/sudoers.d/99_www_data_iptables
chmod 440 /etc/sudoers.d/99_www_data_iptables

# 3. Actualizar la web
cp indexx.php /var/www/html/indexx.php
chown www-data:www-data /var/www/html/indexx.php

echo "¡Fix aplicado! Ve a la máquina cliente y haz la prueba."
