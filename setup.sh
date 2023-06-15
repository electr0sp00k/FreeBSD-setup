#!/bin/sh

#TEO COFFMAN
#CS 596 - NETSEC
#Shell script to turn FreeBSD into a virtual network appliance

#The following features are added:
# - switching (internal to the network) via FreeBSD pf
# - port mirroring via FreeBSD netgraph
# - DHCP server, DNS server via dnsmasq
# - firewall via FreeBSD pf
# - NAT layer via FreeBSD pf
# - flow monitoring via darkstat

# NOTE: this script does not do much other than install and configure
#       the basic needed utilities and configuration to act as a router
#       I suggest installing curl, wget, w3m, and some other utilities
#       if this machine is going to be used for other purposes

#This setup was configured and tested in a hyperV machine and using hyperV
#virtual switches, this should work for all devices that FreeBSD is able to
#be run on, as the utilities used have aarm64 releases
#although it may not work with wifi interfaces, as ethernet interfaces were
#used. This script requires 3 interfaces to be installed on the machine
#LAN: connected to an ethernet switch with client machines
#WAN: connected to the open internet
#MIRROR: this is an interface that will mirror all traffic from LAN and allow
#the setup of a sensor server

# Set your network interfaces names
WAN="hn0"
LAN="hn1"
MIRROR="hn2"

# Install dnsmasq
pkg install -y dnsmasq

# Enable forwarding
echo "net.inet.ip.forwarding=1" >> /etc/sysctl.conf
# Enable immediately
sysctl net.inet.ip.forwarding=1

# Set LAN IP
ifconfig ${LAN} inet 192.168.1.1 netmask 255.255.255.0
# Make IP setting persistent
sysrc "ifconfig_${LAN}=inet 192.168.1.1 netmask 255.255.255.0"

ifconfig ${LAN} up
ifconfig ${LAN} promisc

# Enable dnsmasq on boot
sysrc dnsmasq_enable="YES"

# Edit dnsmasq configuration
echo "interface=${LAN}" >> /usr/local/etc/dnsmasq.conf
echo "dhcp-range=192.168.1.50,192.168.1.150,12h" >> /usr/local/etc/dnsmasq.conf
echo "dhcp-option=option:router,192.168.1.1" >> /usr/local/etc/dnsmasq.conf
# Configure PF for NAT
echo "
ext_if=\"${WAN}\"
int_if=\"${LAN}\"
nat on \$ext_if from \$int_if:network to any -> (\$ext_if)

include \"/etc/pf.blockrules.conf\"

pass in on \$int_if from \$int_if:network to any
pass out on \$ext_if from any to any
" >> /etc/pf.conf

#Firewall rules go in /etc/pf.blockrules.conf
#use the quick keyword to drop packet immediately
#block all icmp from google dns (8.8.8.8) as example
#int_if is lAN , ext_if is WAN


echo "
#Usage: pf firewall, use quick keyword here
#\$int_if
#\$ext_if

block in quick on \$ext_if proto icmp from 8.8.8.8 to any
block out quick on \$ext_if proto icmp from any to 8.8.8.8
" > /etc/pf.blockrules.conf

# Start dnsmasq
service dnsmasq start

# Enable PF on boot
sysrc pf_enable="YES"

# Start PF
service pf start

# Load PF rules
pfctl -f /etc/pf.conf

# Load ng_tee and ng_ether
kldload ng_ether
kldload ng_tee

# Set up ng_tee for LAN and WAN interfaces
ngctl mkpeer ${LAN}: tee upper left
ngctl name ${LAN}:upper TEE_LAN
ngctl connect ${LAN}: TEE_LAN: lower right

ngctl mkpeer ${WAN}: tee upper left
ngctl name ${WAN}:upper TEE_WAN
ngctl connect ${WAN}: TEE_WAN: lower right

# Set up one2many for mirror interface
ngctl mkpeer ${MIRROR}: one2many lower one
ngctl name hn2:lower O2M
ngctl connect TEE_LAN: O2M: right2left many0
ngctl connect TEE_WAN: O2M: right2left many1

# Create /usr/local/etc/rc.d/ngsetup
echo '#!/bin/sh
#
# PROVIDE: ngsetup
# REQUIRE: NETWORKING
# KEYWORD: shutdown
#
# Add the following lines to /etc/rc.conf to enable ngsetup:
#
#ngsetup_enable="YES"

. /etc/rc.subr

name="ngsetup"
start_cmd="${name}_start"

ngsetup_start() {
  kldload ng_ether
  kldload ng_tee
  ngctl mkpeer '${LAN}': tee upper left
  ngctl name '${LAN}':upper TEE_LAN
  ngctl connect '${LAN}': TEE_LAN: lower right
  ngctl mkpeer '${WAN}': tee upper left
  ngctl name '${WAN}':upper TEE_WAN
  ngctl connect '${WAN}': TEE_WAN: lower right
  ngctl mkpeer '${MIRROR}': one2many lower one
  ngctl name hn2:lower O2M
  ngctl connect TEE_LAN: O2M: right2left many0
  ngctl connect TEE_WAN: O2M: right2left many1
}

load_rc_config $name
run_rc_command "$1"
' > /usr/local/etc/rc.d/ngsetup
chmod +x /usr/local/etc/rc.d/ngsetup

# Enable ngsetup on boot
sysrc ngsetup_enable="YES"

sysrc ifconfig_${MIRROR}=up
ifconfig ${MIRROR} up

pkg install -y darkstat
sysrc darkstat_enable="YES"
sysrc darkstat_interface="${WAN}"
service darkstat start
