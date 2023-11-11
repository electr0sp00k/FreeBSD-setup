#!/bin/sh
#
#TEO COFFMAN
#CS 596 - NETSEC
#Shell script to turn FreeBSD into a virtual network appliance
#
#The following features are added:
# - switching (internal to the network) via FreeBSD pf
# - port mirroring via FreeBSD netgraph
# - DHCP server, DNS server via dnsmasq
# - firewall via FreeBSD pf
# - NAT layer via FreeBSD pf
# - flow monitoring via darkstat
#
# NOTE: this script does not do much other than install and configure
#       the basic needed utilities and configuration to act as a router
#       I suggest installing curl, wget, w3m, and some other utilities
#       if this machine is going to be used for other purposes
#
#This setup was configured and tested in a hyperV machine and using hyperV
#virtual switches, this should work for all devices that FreeBSD is able to
#be run on, as the utilities used have aarm64 releases
#although it may not work with wifi interfaces, as ethernet interfaces were
#used. This script requires 2 interfaces to be installed on the machine
#LAN: connected to an ethernet switch with client machines
#WAN: connected to the open internet
#
#These 2 other interfaces are optional, but should be their own ethernet
#interfaces if used. I just created 2 virtual switches in hyperV and
#added them to the appliance machine.
#
#MIRROR_LAN: this is an interface that will mirror all traffic from LAN
#MIRROR_WAN: this is an interface that will mirror all traffic from WAN

#OPTIONS (YES, NO)
#Install darkstat as a flow monitoring utility
OPTION_DARKSTAT="YES"
#setup a mirror port for mirroring LAN traffic
OPTION_MIRRORLAN="YES"
#setup a mirror port for mirroring WAN traffic
OPTION_MIRRORWAN="NO"

# Set your network interfaces names; set these as they appear in ifconfig
# they will not be renamed during the course of installation
WAN="hn0"
LAN="hn1"
MIRROR_LAN="hn2"
MIRROR_WAN="hn3"

# Install dnsmasq
pkg install -y dnsmasq

# Enable forwarding
sysrc gateway_enable="YES"
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
" > /etc/pf.conf

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

# MIRROR INTERFACES
# mirrors all traffic from LAN to MIRROR_LAN
# mirrors all traffic from WAN to MIRROR_WAN
# makes sure sensor server is is promisc mode as the ethernet frames
# are mirrored raw without any processing
# You can also read traffic from the router using:
# tcpdump -i MIRROR_LAN -e -n
# or
# tcpdump -i MIRROR_WAN -e -n
#
#
# NG is awesome, and its a built in utility. I played around with it while
# getting the mirrored ports setup, and damn it has amazing functionality.
# it can send data to sockets for user processes to use, you  can message
# each node and get informatiom; for example ngctl msg TEE_LAN: getstats
# will return the number of frames that have traveled through each hook
# on the tee node. The only nuisance with these things is that they are
# not persistent and a setup script has to be added so that they work on boot
# hence adding the script to /usr/local/etc/rc.d. But after that, the script
# can be set up to start on boot and implement the same netgraph as described
# also try ngctl dot, it returns a graphviz representation of the netgraph to
# stdout, but you can pipe it to a utility that will display it as a graph.
# additionaly, with the one2many node, you could send all traffic from as many
# ethernet ports as youd like to one port.
# there is also a bpf node which can filter packets based on bpf rules which is
# cool. I think that it should be covered in the class as it's own module

if [ "$OPTION_MIRRORLAN" = "YES" ]; then
    # Load ng_tee and ng_ether
    kldload ng_ether
    kldload ng_tee

    # Set up ng_tee for LAN interface
    ngctl mkpeer ${LAN}: tee upper left
    ngctl name ${LAN}:upper TEE_LAN
    ngctl connect ${LAN}: TEE_LAN: lower right

    # Set up one2many for MIRROR_LAN interface
    ngctl mkpeer ${MIRROR_LAN}: one2many lower one
    ngctl name ${MIRROR_LAN}:lower O2M_LAN
    ngctl connect TEE_LAN: O2M_LAN: right2left many0
    ngctl connect TEE_LAN: O2M_LAN: left2right many1

    # Create /usr/local/etc/rc.d/ngsetupLAN
    echo '#!/bin/sh
#
# PROVIDE: ngsetupLAN
# REQUIRE: NETWORKING
# KEYWORD: shutdown
#
# Add the following lines to /etc/rc.conf to enable ngsetupLAN:
#
#ngsetupLAN_enable="YES"

. /etc/rc.subr

name="ngsetupLAN"
start_cmd="${name}_start"

ngsetupLAN_start() {
    kldload ng_ether
    kldload ng_tee
    ngctl mkpeer '${LAN}': tee upper left
    ngctl name '${LAN}':upper TEE_LAN
    ngctl connect '${LAN}': TEE_LAN: lower right
    ngctl mkpeer '${MIRROR_LAN}': one2many lower one
    ngctl name '${MIRROR_LAN}':lower O2M_LAN
    ngctl connect TEE_LAN: O2M_LAN: right2left many0
    ngctl connect TEE_LAN: O2M_LAN: left2right many1
}

load_rc_config $name
run_rc_command "$1"
' > /usr/local/etc/rc.d/ngsetupLAN
    chmod +x /usr/local/etc/rc.d/ngsetupLAN

    # Enable ngsetup on boot
    sysrc ngsetupLAN_enable="YES"

    sysrc ifconfig_${MIRROR_LAN}=up
    ifconfig ${MIRROR_LAN} up
fi

if [ "$OPTION_MIRRORWAN" = "YES" ]; then
    # Load ng_tee and ng_ether
    kldload ng_ether
    kldload ng_tee

    # Set up ng_tee for WAN interface
    ngctl mkpeer ${WAN}: tee upper left
    ngctl name ${WAN}:upper TEE_WAN
    ngctl connect ${WAN}: TEE_WAN: lower right

    # Set up one2many for MIRROR_WAN interface
    ngctl mkpeer ${MIRROR_WAN}: one2many lower one
    ngctl name ${MIRROR_WAN}:lower O2M_WAN
    ngctl connect TEE_WAN: O2M_WAN: right2left many0
    ngctl connect TEE_WAN: O2M_WAN: left2right many1

    # Create /usr/local/etc/rc.d/ngsetupWAN
    echo '#!/bin/sh
#
# PROVIDE: ngsetupWAN
# REQUIRE: NETWORKING
# KEYWORD: shutdown
#
# Add the following lines to /etc/rc.conf to enable ngsetupWAN:
#
#ngsetupWAN_enable="YES"

. /etc/rc.subr

name="ngsetupWAN"
start_cmd="${name}_start"

ngsetupWAN_start() {
    kldload ng_ether
    kldload ng_tee
    ngctl mkpeer '${WAN}': tee upper left
    ngctl name '${WAN}':upper TEE_WAN
    ngctl connect '${WAN}': TEE_WAN: lower right
    ngctl mkpeer '${MIRROR_WAN}': one2many lower one
    ngctl name '${MIRROR_WAN}':lower O2M_WAN
    ngctl connect TEE_WAN: O2M_WAN: right2left many0
    ngctl connect TEE_WAN: O2M_WAN: left2right many1
}

load_rc_config $name
run_rc_command "$1"
' > /usr/local/etc/rc.d/ngsetupWAN
    chmod +x /usr/local/etc/rc.d/ngsetupWAN

    # Enable ngsetup on boot
    sysrc ngsetupWAN_enable="YES"

    sysrc ifconfig_${MIRROR_WAN}=up
    ifconfig ${MIRROR_WAN} up
fi

#DARKSTAT! AWESOME!
#Listens on WAN port 67 and records data on traffic flow and does stuff
#connect to the ip of WAN you should be able to connect to it if WAN is hyperV
#default port (your machine is connected to the WAN interface in Windows).
#Otherwise you can check on loopback on the router using:
# curl 127.0.0.1:67 | w3m -dump -T text/html
#Has some cool functionality including stats on IPs and their traffic
#I sent 12,245 ping packets to yahoo before they blocked me permanently


if [ "${OPTION_DARKSTAT}" = "YES" ]; then
  pkg install -y darkstat
  sysrc darkstat_enable="YES"
  sysrc darkstat_interface="${WAN}"
  service darkstat start
fi
