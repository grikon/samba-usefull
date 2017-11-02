#!/bin/bash
# This script helps with debugging problems
. ./functions.sh
. ./env_vars.sh

smbclient -L localhost -U%
echo "$ADMINPASSWORD" | smbclient //localhost/netlogon -UAdministrator -c 'ls'

host -t SRV _ldap._tcp.$DOMAIN
host -t SRV _kerberos._udp.$DOMAIN
host -t A $(hostname)

echo "$ADMINPASSWORD" | kinit Administrator@$REALM
klist
