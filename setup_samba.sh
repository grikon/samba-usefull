#!/bin/bash

dir_script=`dirname $0`
dir_config="$dir_script/cfgs"
#dir_libs="$dir_script/libs"
#dir_data_repos="$dir_script/data_repos"

#install all pre-reqs
echo "Установка необходимых пакетов для ОС"
yum -y install gcc libacl-devel libblkid-devel gnutls-devel \
   readline-devel python-devel gdb pkgconfig krb5-workstation \
   zlib-devel setroubleshoot-server libaio-devel \
   setroubleshoot-plugins policycoreutils-python \
   libsemanage-python python-setuptools setools-libs \
   popt-devel libpcap-devel sqlite-devel libidn-devel \
   libxml2-devel libacl-devel libsepol-devel libattr-devel \
   keyutils-libs-devel cyrus-sasl-devel cups-devel bind-utils \
   docbook-style-xsl libxslt perl gamin-devel openldap-devel \
   perl-Parse-Yapp xfsprogs-devel NetworkManager \
   samba samba-client samba-dc samba-krb5-printing \
   samba-test tdb-tools krb5-workstation samba-winbind-clients \
   openldap-clients bind bind-utils python-dns nmap-ncat dhcp

# configure
echo "Настройка операционной системы "ОСь"... "

. ./functions.sh
. ./env_vars.sh

systemctl stop NetworkManager


echo "Временные настройки DNS..."

cat <<EOF > /etc/resolv.conf
nameserver 8.8.8.8
EOF

echo "Установка точного времени"config.php

yum install -y ntpdate ntp
enableService ntpd
startService  ntpd

DATETIME=`date +%Y%m%d_%H%M%S`

echo "Инициализация и настройка домена $DOMAIN..."

#for service in smb nmb slapd named; do chkconfig $service off; service $service stop;
rm -rf /etc/samba/smb.conf
rm -rf /var/lib/samba/private/*
rm -rf /etc/krb5.conf
samba-tool domain provision --use-rfc2307 --dns-backend=BIND9_DLZ --realm=$DOMAIN --domain=$SHORTDOMAIN --adminpass=$ADMINPASSWORD --server-role=dc --use-xattrs=yes
rndc-confgen -a -r /dev/urandom

cat <<EOF > /var/named/forwarders.conf
forwarders { 8.8.8.8; 8.8.4.4; } ;
EOF

IP=`hostname -I`
echo $IP | grep -q " "
if [[ $? != 1 ]]
then
    echo "Multiple interfaces on this host.  Set IP manually"
    exit 1
fi

cp -p /etc/named.conf /etc/named.conf.$DATETIME
cat <<EOF > /etc/named.conf
options {
        listen-on port 53 { 127.0.0.1; $IP; };
//        listen-on-v6 port 53 { any; };

        directory       "/var/named";
        dump-file       "/var/named/data/cache_dump.db";
        statistics-file "/var/named/data/named_stats.txt";
        memstatistics-file "/var/named/data/named_mem_stats.txt";
        allow-query     { localnets; };
        recursion yes;

        dnssec-enable no;
        dnssec-validation no;
//        dnssec-enable yes;
//        dnssec-validation yes;
//        dnssec-lookaside auto;

        /* Path to ISC DLV key */
        bindkeys-file "/etc/named.iscdlv.key";

        managed-keys-directory "/var/named/dynamic";

        tkey-gssapi-keytab "/var/lib/samba/private/dns.keytab";

        include "forwarders.conf";

};

logging {
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};

zone "." IN {
        type hint;
        file "named.ca";
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
include "/var/lib/samba/private/named.conf";
include "/etc/rndc.key";

EOF

#mv /etc/krb5.conf /etc/krb5.conf.$DATETIME
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
chgrp named /etc/krb5.conf

cp -p /etc/sysconfig/named /etc/sysconfig/named.$DATETIME
echo OPTIONS="-4" >> /etc/sysconfig/named

echo "Настройка прав доступа и контекстов безопасности для домена" 
chown -R named:named /var/lib/samba/private/dns
chown -R named:named /var/lib/samba/private/sam.ldb.d
chown named:named /var/lib/samba/private/dns.keytab
chown named:named /etc/rndc.key
chown named:named /var/lib/samba/private/named.conf
chown root:named /var/lib/samba/private/
chmod 775 /var/lib/samba/private/
chgrp ntp /var/lib/samba/ntp_signd/
chmod g+rx /var/lib/samba/ntp_signd/

systemctl stop ntpd
systemctl start ntpd

#rm -rf /etc/selinux/targeted/semanage.*.LOCK
setsebool -P samba_domain_controller on
chcon -t named_conf_t /var/lib/samba/private/dns.keytab
semanage fcontext -a -t named_conf_t /var/lib/samba/private/dns.keytab
chcon -t named_conf_t /var/lib/samba/private/named.conf
semanage fcontext -a -t named_conf_t /var/lib/samba/private/named.conf
chcon -t named_var_run_t /var/lib/samba/private/dns
semanage fcontext -a -t named_var_run_t /var/lib/samba/private/dns
chcon -t named_var_run_t /var/lib/samba/private/dns/sam.ldb
semanage fcontext -a -t named_var_run_t /var/lib/samba/private/dns/sam.ldb
chcon -t named_var_run_t /var/lib/samba/private/dns/sam.ldb.d
semanage fcontext -a -t named_var_run_t /var/lib/samba/private/dns/sam.ldb.d
for file in `ls /var/lib/samba/private/dns/sam.ldb.d`
do
    chcon -t named_var_run_t /var/lib/samba/private/dns/sam.ldb.d/$file
    semanage fcontext -a -t named_var_run_t /var/lib/samba/private/dns/sam.ldb.d/$file
done
for file in `ls /var/lib/samba/private/sam.ldb.d`
do
    chcon -t named_var_run_t /var/lib/samba/private/sam.ldb.d/$file
    semanage fcontext -a -t named_var_run_t /var/lib/samba/private/sam.ldb.d/$file
done
restorecon -vR /var/lib/samba/

echo "Настройка межсетевого экрана Firewalld..."
firewall-cmd --add-port=53/tcp --permanent;
firewall-cmd --add-port=53/udp --permanent;
firewall-cmd --add-port=88/tcp --permanent;
firewall-cmd --add-port=88/udp --permanent; \
firewall-cmd --add-port=135/tcp --permanent;
firewall-cmd --add-port=137-138/udp --permanent;
firewall-cmd --add-port=139/tcp --permanent; \
firewall-cmd --add-port=389/tcp --permanent;
firewall-cmd --add-port=389/udp --permanent;
firewall-cmd --add-port=445/tcp --permanent; \
firewall-cmd --add-port=464/tcp --permanent;
firewall-cmd --add-port=464/udp --permanent;
firewall-cmd --add-port=636/tcp --permanent; \
firewall-cmd --add-port=1024-5000/tcp --permanent;
firewall-cmd --add-port=3268-3269/tcp --permanent
firewall-cmd --reload


echo "Запуск службы DNS..."
enableService named
startService named

# Switching to internal DNS...
cat <<EOF > /etc/resolv.conf
nameserver $DNS1
search $DOMAIN
EOF

cat <<EOF > /etc/init.d/samba4
#!/bin/bash
#
# samba4        This shell script takes care of starting and stopping
#               samba4 daemons.
#
# chkconfig: - 58 74
# description: Samba 4 acts as an Active Directory Domain Controller.

### BEGIN INIT INFO
# Provides: samba4
# Required-Start: \$network \$local_fs \$remote_fs
# Required-Stop: \$network \$local_fs \$remote_fs
# Should-Start: \$syslog \$named
# Should-Stop: \$syslog \$named
# Short-Description: start and stop samba4
# Description: Samba 4 acts as an Active Directory Domain Controller.
### END INIT INFO


# Source function library.
. /etc/init.d/functions


# Source networking configuration.
. /etc/sysconfig/network


prog=samba
prog_args="-d2 -l /var/log/ -D"
prog_dir=/usr/sbin/
lockfile=/var/lock/subsys/\$prog


start() {
        [ "\$NETWORKING" = "no" ] && exit 1

        # Start daemons.
        echo -n $"Starting samba4: "
        daemon \$prog_dir/\$prog \$prog_args
        RETVAL=\$?
        echo
        [ \$RETVAL -eq 0 ] && touch \$lockfile
        return \$RETVAL
}


stop() {
        [ "\$EUID" != "0" ] && exit 4
        echo -n $"Shutting down samba4: "
        killproc \$prog_dir/\$prog
        RETVAL=\$?
        echo
        [ \$RETVAL -eq 0 ] && rm -f \$lockfile
        return \$RETVAL
}


# See how we were called.
case "\$1" in
start)
        start
        ;;
stop)
        stop
        ;;
status)
        status \$prog
        ;;
restart)
        stop
        start
        ;;
reload)
        echo "Not implemented yet."
        exit 3
        ;;
*)
        echo $"Usage: \$0 {start|stop|status|restart|reload}"
        exit 2
esac

EOF

chmod 555 /etc/init.d/samba4

echo "Запуск службы SAMBA Active Directory Domain Controller..."
enableService samba4
startService samba4

# Run samba like this to test
#/usr/sbin/samba -i -M single -d2

# Run named like this to test
#named -u named -4 -f -g -d2

echo "Настройка правил пароля для доменных пользователей..."
samba-tool domain passwordsettings set --complexity=off
samba-tool domain passwordsettings set --history-length=0
samba-tool domain passwordsettings set --min-pwd-age=0
samba-tool domain passwordsettings set --max-pwd-age=0
samba-tool domain passwordsettings set --min-pwd-length=6

echo "Создание и настройка служебного пользователя домена dhcpd..."
samba-tool user create dhcpd --description="Unprivileged user for DNS updates via DHCP server" --random-password
samba-tool user setexpiry dhcpd --noexpiry
samba-tool group addmembers DnsAdmins dhcpd
samba-tool group addmembers DnsUpdateProxy dhcpd
samba-tool domain exportkeytab --principal=dhcpd@$REALM /etc/dhcp/dhcpd.keytab
chown dhcpd.dhcpd /etc/dhcp/dhcpd.keytab
systemctl enable dhcpd

cp -f $dir_config/dhcpd.conf /etc/dhcp/

#cp -f $dir_config/dhcpd-update-samba-dns.conf /etc/dhcp/
#cp -f $dir_config/dhcpd-update-samba-dns.sh /usr/local/bin/
#cp -f $dir_config/samba-dnsupdate.sh /usr/local/bin/

cp -f $dir_config/dhcpd-update.sh /usr/local/bin/
cp -f $dir_config/ntp.conf /etc/
chown dhcpd.dhcpd /usr/local/bin/*.sh
chmod +x /usr/local/bin/dhcpd-update.sh
chown -R dhcpd.dhcpd /etc/dhcp
systemctl start dhcpd

systemctl enable ntpd
systemctl start ntpd

#echo "Создание обратной	зоны DNS..."
#samba-­tool dns zonecreate $HOSTNAME 1.168.192.in­addr.arpa
#samba­-tool dns add 1.168.192.in­addr.arpa 2 PTR $HOSTNAME

echo "Создание тестовых пользователей user1 и user2..."
samba-tool user create user1 Passw0rd --must-change-at-next-login --surname=Sidorov --given-name=sidorov --mail-address='user1@tver.trs' --uid=user1 --uid-number=10000 --gid-number=10000 --login-shell=/bin/bash
samba-tool user create user2 Passw0rd --must-change-at-next-login --surname=Petrov --given-name=petrov  --mail-address='user2@tver.trs' --uid=user2 --uid-number=10001 --gid-number=10000 --login-shell=/bin/bash

echo "Конфигурирование утилиты администрирования контроллера домена SAMBA AD DC"
yum -y install phpldapadmin
cp -f $dir_config/phpldapadmin/config.php /etc/phpldapadmin/
cp -f $dir_config/phpldapadmin/phpldapadmin.conf /etc/httpd/conf.d/
systemctl restart httpd.service

echo "Now manually set the group id and NIS domain using dsa.msc"
# Change passwords like this (on domain controller box)
#samba-tool user setpassword user1
samba-tool fsmo show

#echo "Проверка имени хостов и динамического обновления зоны DNS"
#host -t SRV _kerberos._udp.$DOMAIN.
#host -t SRV _ldap._tcp.$DOMAIN.
#host -t A $HOSTNAME.
#samba_dnsupdate --verbose --all-names
