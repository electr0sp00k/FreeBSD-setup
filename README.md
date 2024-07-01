# README

## Overview

This shell script, created by Teo Coffman for the CS 596 - Network Security course, is designed to transform a FreeBSD machine into a virtual network appliance. The script installs and configures essential network utilities and configurations, enabling the FreeBSD machine to function as a router with added features like switching, port mirroring, DHCP/DNS services, firewall, NAT, and flow monitoring.

## Features

- **Switching**: Internal network switching via FreeBSD's `pf`
- **Port Mirroring**: Utilizing FreeBSD's `netgraph` for traffic mirroring
- **DHCP/DNS Server**: Implemented using `dnsmasq`
- **Firewall**: Configured with FreeBSD's `pf`
- **NAT Layer**: Configured with FreeBSD's `pf`
- **Flow Monitoring**: Provided by `darkstat`

## Requirements

- **FreeBSD**: This script is tailored for FreeBSD and has been tested in a Hyper-V environment.
- **Interfaces**: At least two network interfaces (LAN and WAN). Optional additional interfaces for traffic mirroring.

## Usage

1. **Install and Enable Services**
    - `dnsmasq` for DHCP/DNS services.
    - `darkstat` for flow monitoring (optional).
    - Configure packet forwarding and NAT using `pf`.

2. **Network Interfaces Configuration**
    - Set the LAN interface IP and enable promiscuous mode.
    - Enable packet forwarding.

3. **Port Mirroring Setup**
    - Configured using `netgraph` for both LAN and WAN interfaces.

## Configuration

### Network Interfaces

Set your network interface names in the script:

```sh
WAN="hn0"
LAN="hn1"
MIRROR_LAN="hn2"
MIRROR_WAN="hn3"
```

### Options

Configure options for additional features:

- Install `darkstat`: `OPTION_DARKSTAT="YES"`
- Setup LAN traffic mirroring: `OPTION_MIRRORLAN="YES"`
- Setup WAN traffic mirroring: `OPTION_MIRRORWAN="NO"`

### Installation and Configuration

1. **Install dnsmasq**

    ```sh
    pkg install -y dnsmasq
    ```

2. **Enable IP Forwarding**

    ```sh
    sysrc gateway_enable="YES"
    sysctl net.inet.ip.forwarding=1
    ```

3. **Configure LAN Interface**

    ```sh
    ifconfig ${LAN} inet 192.168.1.1 netmask 255.255.255.0
    sysrc "ifconfig_${LAN}=inet 192.168.1.1 netmask 255.255.255.0"
    ifconfig ${LAN} up
    ifconfig ${LAN} promisc
    ```

4. **Configure dnsmasq**

    ```sh
    sysrc dnsmasq_enable="YES"
    echo "interface=${LAN}" >> /usr/local/etc/dnsmasq.conf
    echo "dhcp-range=192.168.1.50,192.168.1.150,12h" >> /usr/local/etc/dnsmasq.conf
    echo "dhcp-option=option:router,192.168.1.1" >> /usr/local/etc/dnsmasq.conf
    service dnsmasq start
    ```

5. **Configure PF for NAT and Firewall**

    Create `/etc/pf.conf`:

    ```sh
    echo "
    ext_if="${WAN}"
    int_if="${LAN}"
    nat on \$ext_if from \$int_if:network to any -> (\$ext_if)
    include "/etc/pf.blockrules.conf"
    pass in on \$int_if from \$int_if:network to any
    pass out on \$ext_if from any to any
    " > /etc/pf.conf
    ```

    Create `/etc/pf.blockrules.conf` for firewall rules:

    ```sh
    echo "
    block in quick on \$ext_if proto icmp from 8.8.8.8 to any
    block out quick on \$ext_if proto icmp from any to 8.8.8.8
    " > /etc/pf.blockrules.conf
    ```

    Enable and start PF:

    ```sh
    sysrc pf_enable="YES"
    service pf start
    pfctl -f /etc/pf.conf
    ```

6. **Port Mirroring Setup (Optional)**

    If port mirroring is enabled:

    ```sh
    if [ "$OPTION_MIRRORLAN" = "YES" ]; then
        kldload ng_ether
        kldload ng_tee
        ngctl mkpeer ${LAN}: tee upper left
        ngctl name ${LAN}:upper TEE_LAN
        ngctl connect ${LAN}: TEE_LAN: lower right
        ngctl mkpeer ${MIRROR_LAN}: one2many lower one
        ngctl name ${MIRROR_LAN}:lower O2M_LAN
        ngctl connect TEE_LAN: O2M_LAN: right2left many0
        ngctl connect TEE_LAN: O2M_LAN: left2right many1
        sysrc ngsetupLAN_enable="YES"
        sysrc ifconfig_${MIRROR_LAN}=up
        ifconfig ${MIRROR_LAN} up
    fi

    if [ "$OPTION_MIRRORWAN" = "YES" ]; then
        kldload ng_ether
        kldload ng_tee
        ngctl mkpeer ${WAN}: tee upper left
        ngctl name ${WAN}:upper TEE_WAN
        ngctl connect ${WAN}: TEE_WAN: lower right
        ngctl mkpeer ${MIRROR_WAN}: one2many lower one
        ngctl name ${MIRROR_WAN}:lower O2M_WAN
        ngctl connect TEE_WAN: O2M_WAN: right2left many0
        ngctl connect TEE_WAN: O2M_WAN: left2right many1
        sysrc ngsetupWAN_enable="YES"
        sysrc ifconfig_${MIRROR_WAN}=up
        ifconfig ${MIRROR_WAN} up
    fi
    ```

7. **Flow Monitoring with darkstat (Optional)**

    ```sh
    if [ "${OPTION_DARKSTAT}" = "YES" ]; then
      pkg install -y darkstat
      sysrc darkstat_enable="YES"
      sysrc darkstat_interface="${WAN}"
      service darkstat start
    fi
    ```

## Notes

- This script primarily installs and configures the basic utilities for the router. Additional tools like `curl`, `wget`, and `w3m` are recommended if the machine is used for other purposes.
- The script has been tested in a Hyper-V environment with Hyper-V virtual switches. Ensure compatibility with your specific setup.
- Ensure to have at least two network interfaces (LAN and WAN) connected appropriately. Additional interfaces for mirroring are optional but should be separate Ethernet interfaces.

By following the steps and configurations provided in this README, you can successfully set up your FreeBSD machine as a versatile virtual network appliance.
