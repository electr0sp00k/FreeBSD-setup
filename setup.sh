#!/bin/sh

# Install FreeBSD, this part depends on your specific hardware and cannot be done through a script

# Set your network interfaces names
WAN="hn0"
LAN="hn1"
MIRROR="hn2"

# Install dnsmasq
pkg install dnsmasq -y

# Enable dnsmasq on boot
sysrc dnsmasq_enable="YES"

# Start dnsmasq
service dnsmasq start

# Edit dnsmasq configuration
echo "interface=$LAN" >> /usr/local/etc/dnsmasq.conf
echo "dhcp-range=192.168.1.50,192.168.1.150,12h" >> /usr/local/etc/dnsmasq.conf
echo "dhcp-option=option:router,192.168.1.1" >> /usr/local/etc/dnsmasq.conf

# Set LAN IP
ifconfig $LAN inet 192.168.1.1 netmask 255.255.255.0

# Make IP setting persistent
echo "ifconfig_$LAN=\"inet 192.168.1.1 netmask 255.255.255.0\"" >> /etc/rc.conf

# Enable forwarding
echo "net.inet.ip.forwarding=1" >> /etc/sysctl.conf

# Enable immediately
sysctl net.inet.ip.forwarding=1

# Configure PF for NAT
echo "
ext_if=\"$WAN\"
int_if=\"$LAN\"
nat on \$ext_if from \$int_if:network to any -> (\$ext_if)
pass in on \$int_if from \$int_if:network to any
pass out on \$ext_if from any to any
" >> /etc/pf.conf

# Enable PF on boot
echo "pf_enable=\"YES\"" >> /etc/rc.conf

# Start PF
service pf start

# Load PF rules
pfctl -f /etc/pf.conf

# Load ng_tee and ng_ether
kldload ng_ether
kldload ng_tee

# Set up ng_tee for LAN and WAN interfaces
ngctl mkpeer $LAN: tee upper left
ngctl name $LAN:upper TEE_LAN
ngctl connect $LAN: TEE_LAN: lower right

ngctl mkpeer $WAN: tee upper left
ngctl name $WAN:upper TEE_WAN
ngctl connect $WAN: TEE_WAN: lower right

# Set up one2many for mirror interface
ngctl mkpeer $MIRROR: one2many lower one
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
  ngctl mkpeer '$LAN': tee upper left
  ngctl name '$LAN':upper TEE_LAN
  ngctl connect '$LAN': TEE_LAN: lower right
  ngctl mkpeer '$WAN': tee upper left
  ngctl name '$WAN':upper TEE_WAN
  ngctl connect '$WAN': TEE_WAN: lower right
  ngctl mkpeer '$MIRROR': one2many lower one
  ngctl name hn2:lower O2M
  ngctl connect TEE_LAN: O2M: right2left many0
  ngctl connect TEE_WAN: O2M: right2left many1
}

load_rc_config $name
run_rc_command "$1"
' > /usr/local/etc/rc.d/ngsetup
chmod +x /usr/local/etc/rc.d/ngsetup

# Enable ngsetup on boot
echo "ngsetup_enable=\"YES\"" >> /etc/rc.conf
