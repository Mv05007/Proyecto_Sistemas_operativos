sudo su -
iptables -F
iptables -t nat -F
iptables -X
iptables -t nat -X
systemctl stop dnsmasq
systemctl disable dnsmasq
rm -f /etc/dnsmasq.conf
rm -f /etc/sudoers.d/99_www_data_iptables
apt-get remove --purge dnsmasq -y
apt-get install dnsmasq -y   # Lo reinstalamos limpio
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ipforward.conf
sysctl -p /etc/sysctl.d/99-ipforward.conf
exit
