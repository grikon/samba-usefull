#!/bin/bash

. ./env_vars.sh

if [[ `tty` != "/dev/tty1" ]]
then
    echo "Run this from the console, not ssh"
    exit 1
fi

if [[ `hostname` = "localhost.localdomain" ]]
then
    echo Must set hostname in /etc/hostname or /etc/sysconfig/network
    exit 1
fi

DATETIME=`date +%Y%m%d_%H%M%S`

. ./functions.sh

echo "Installing NetworkManager..."
yum -y install NetworkManager

echo "Disabling old-style network service..."
stopService network
disableService network
echo "Enabling NetworkManager..."
enableService NetworkManager
startService NetworkManager

echo "Setting up network (eg DNS)..."
IFCFG=`ls /etc/sysconfig/network-scripts/ifcfg-* | grep -v ifcfg-lo`
IFCFG=`echo $IFCFG | sed -s "s#/etc/sysconfig/network-scripts/##g"`
IFNAME=`echo $IFCFG | sed -s "s/ifcfg-//g"`
HWADDR=`ifconfig | grep ether | cut -c 15-31`
UUID=`uuidgen`

cp -p /etc/sysconfig/network-scripts/$IFCFG /etc/sysconfig/network-scripts/$DATETIME.ifcfg

cat <<EOF > /etc/sysconfig/network-scripts/$IFCFG
TYPE="Ethernet"
BOOTPROTO="dhcp"
DEFROUTE="yes"
IPV4_FAILURE_FATAL="no"
IPV6INIT=no
IPV6_AUTOCONF="yes"
IPV6_DEFROUTE="yes"
IPV6_FAILURE_FATAL="no"
NAME="$IFNAME"
UUID="$UUID"
ONBOOT="yes"
DNS1=$DNS1
IPV6_PEERDNS=yes
IPV6_PEERROUTES=yes
HWADDR=$HWADDR
PEERDNS=no
PEERROUTES=yes
SEARCH=$DOMAIN
EOF

cp -p /etc/resolv.conf /etc/resolv.conf.$DATETIME
cat <<EOF > /etc/resolv.conf
nameserver $DNS1
search $DOMAIN
EOF

restartService NetworkManager
echo "Done."
