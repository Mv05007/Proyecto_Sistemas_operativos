#!/bin/bash
# Este script se ejecuta al inicio para bloquear los dominios no deseados
/sbin/iptables -A FORWARD -d 157.240.0.0/16 -j DROP      # Instagram (bloque aproximado)
/sbin/iptables -A FORWARD -d 34.0.0.0/16 -j DROP        # ChatGPT/OpenAI (aproximado)
/sbin/iptables -A FORWARD -d 35.0.0.0/16 -j DROP        # ChatGPT/OpenAI (complemento)
# Nota: Estos rangos IP son orientativos; para bloquear por dominio exacto necesitarías un proxy.
# Pero para tu proyecto académico, esto es suficiente y funcional.
