#!/bin/bash
# Script que recibe una IP y la autoriza en el firewall (posición 4)
/usr/sbin/iptables -I FORWARD 4 -s "$1" -j ACCEPT
