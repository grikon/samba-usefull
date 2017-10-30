#!/bin/bash

# configure
echo "Настройка операционной системы "ОСь"... "
. ./functions.sh
. ./env_vars.sh

#echo "$IP $(hostname)" >> /etc/hosts && \
cp /etc/hosts /etc/hosts.bak
cat <<EOF > /etc/hosts
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
$IP $(hostname) $(hostname -s)
EOF

echo "Конфигурирование репозитория os-rt-base"
chmod -R 755 /var/www/html/os-rt-base

cat <<EOF > /etc/httpd/conf.d/repos.conf
Alias /repos /var/www/html/os-rt-base/
<directory /var/www/html/os-rt-base>
Options +Indexes
Require all granted
</directory>
EOF

systemctl enable httpd
systemctl start httpd

cat <<EOF > /etc/yum.repos.d/os-rt-base.repo
[os-rt-base]
name=Operating system OS-RT 2.1 - Base
#baseurl=http://betapkgs.os-rt.ru/os-rt/$releasever/os/$basearch/
baseurl=http://$IP/repos
metadata_expire=14d
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-NCI
skip_if_unavailable=True
EOF

restorecon -vR /var/www/html
yum clean all
yum repolist

echo "Настройка DNS /etc/resolv.conf"
cat <<EOF > /etc/resolv.conf
domain $DOMAIN
search $DOMAIN
nameserver $DNS1
nameserver 8.8.8.8
EOF

echo "Установка необходимого ПО"
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

echo "Установка точного времени, настройка локального NTP-сервера"
yum install -y ntpdate ntp
mv /etc/localtime /etc/localtime.bak
ln -s /usr/share/zoneinfo/Europe/Moscow /etc/localtime
cp -f $dir_config/ntp.conf /etc/
enableService ntpd
startService  ntpd

DATETIME=`date +%Y%m%d_%H%M%S`
echo "Подготовка среды ОС..."
#for service in smb nmb slapd named; do chkconfig $service off; service $service stop;
mv /etc/samba/smb.conf /etc/smb.conf.$DATETIME
rm -rf /var/lib/samba
#rm -rf /etc/krb5.conf

cat <<EOF > /etc/krb5.conf
#includedir /etc/krb5.conf.d/
EOF
#rm -rf /usr/local/bin/*
kdestroy

echo "Инициализация и настройка домена $DOMAIN..."
samba-tool domain provision --use-rfc2307 --dns-backend=BIND9_DLZ --realm=$DOMAIN --domain=$SHORTDOMAIN --host-ip=$IP --adminpass=$ADMINPASSWORD --server-role=dc --use-xattrs=yes 
rndc-confgen -a -r /dev/urandom

cat <<EOF > /var/named/forwarders.conf
forwarders { 8.8.8.8; 8.8.4.4; } ;
EOF

#IP=`hostname -I`
#echo $IP | grep -q " "
#if [[ $? != 1 ]]
#then
#    echo "Multiple interfaces on this host.  Set IP manually"
#    exit 1
#fi

#cp -p /etc/named.conf /etc/named.conf.$DATETIME
cat <<EOF > /etc/named.conf
options {
        listen-on port 53 { 127.0.0.1; $IP; };
//        listen-on-v6 port 53 { any; };

        directory       "/var/named";
        dump-file       "/var/named/data/cache_dump.db";
        statistics-file "/var/named/data/named_stats.txt";
        memstatistics-file "/var/named/data/named_mem_stats.txt";
        allow-query     { localnets; $SUBNET/$PREFIX; };
	allow-update     { localnets; $SUBNET/$PREFIX; };
        recursion yes;

        dnssec-enable no;
        dnssec-validation no;
	auth-nxdomain	yes;
//        dnssec-enable yes;
//        dnssec-validation yes;
//        dnssec-lookaside auto;

        /* Path to ISC DLV key */
        bindkeys-file "/etc/named.iscdlv.key";

        managed-keys-directory "/var/named/dynamic";

        tkey-gssapi-keytab "/var/lib/samba/private/dns.keytab";
	allow-transfer { "none"; };
	tkey-domain "$DOMAIN";

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

mv /etc/krb5.conf /etc/krb5.conf.$DATETIME
cp /var/lib/samba/private/krb5.conf /etc/
chgrp named /etc/krb5.conf

#cp -p /etc/sysconfig/named /etc/sysconfig/named.$DATETIME
echo OPTIONS="-4" >> /etc/sysconfig/named

echo "Настройка прав доступа и контекстов безопасности для домена" 
chown -R named:named /var/lib/samba/private/dns
chown -R named:named /var/lib/samba/private/sam.ldb.d
chown named:named /var/lib/samba/private/dns.keytab
chown named:named /etc/rndc.key
chown named:named /var/lib/samba/private/named.conf
chown root:named /var/lib/samba/private/
chmod 775 /var/lib/samba/private/

systemctl restart ntpd

chgrp ntp /var/lib/samba/ntp_signd/
chmod g+rx /var/lib/samba/ntp_signd/

rm -rf /etc/selinux/targeted/semanage.*.LOCK
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

echo "Настройка правил межсетевого экрана Firewalld..."
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
prog_dir=/usr/sbin
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

echo "Запуск и настройка службы SAMBA Active Directory Domain Controller..."
cp -f $dir_config/smb.conf /etc/samba/

#touch /etc/samba/smbpasswd
cat <<EOF > /etc/samba/username.map
!root = $SHORTDOMAIN\$Administrator
EOF
smbpasswd -a root
smbpasswd -e root
enableService samba4
#startService samba4

# Run samba like this to test
#/usr/sbin/samba -i -M single -d2

# Run named like this to test
#named -u named -4 -f -g -d2

echo "Настройка правил пароля для доменных пользователей..."
echo "$ADMINPASSWORD" | kinit Administrator@$REALM
samba-tool domain passwordsettings set --complexity=off --history-length=0 --min-pwd-age=0 --max-pwd-age=0 --min-pwd-length=6

echo "Создание и настройка служебного пользователя домена dhcpd..."
samba-tool user create dhcpd --description="Unprivileged user for DNS updates via DHCP server" --random-password
samba-tool user setexpiry dhcpd --noexpiry
samba-tool group addmembers DnsAdmins dhcpd
samba-tool group addmembers DnsUpdateProxy dhcpd
install -vdm 755 /etc/dhcp
samba-tool domain exportkeytab --principal=dhcpd@$REALM /etc/dhcp/dhcpd.keytab
chown dhcpd.dhcpd /etc/dhcp/dhcpd.keytab
smbpasswd -e dhcpd
cp -f $dir_config/dhcpd.conf /etc/dhcp/

#cp -f $dir_config/dhcpd-update-samba-dns.conf /etc/dhcp/
#cp -f $dir_config/dhcpd-update-samba-dns.sh /usr/local/bin/
#cp -f $dir_config/samba-dnsupdate.sh /usr/local/bin/

cp -f $dir_config/dhcpd-update.sh /etc/dhcp/scripts/
chmod u+x /etc/dhcp/scripts/dhcpd-update.sh
chown -R dhcpd.dhcpd /etc/dhcp

systemctl stop samba4
systemctl enable dhcpd 
systemctl start dhcpd
systemctl enable ntpd
systemctl stop named
systemctl start samba4

echo "Создание обратной зоны DNS..."
#echo "$ADMINPASSWORD" | kinit Administrator@$REALM
klist
samba-tool dns zonelist $(hostname) --username=$Administrator --password="$ADMINPASSWORD"
samba-tool dns zonecreate $(hostname) 1.168.192.in-addr.arpa --username=$Administrator --password="$ADMINPASSWORD"
samba-tool dns add 1.168.192.in-addr.arpa 2 PTR $(hostname)
samba_dnsupdate --all-names --current-ip=$IP

echo "Создание тестовых пользователей user1 и user2..."

samba-tool user create user1 Passw0rd --must-change-at-next-login --given-name=Tester1 --mail-address='user1@tver.trs' --uid=user1 --uid-number=10000 --gid-number=10000 --login-shell=/bin/bash
samba-tool user create user2 Passw0rd --must-change-at-next-login --given-name=Tester2  --mail-address='user2@tver.trs' --uid=user2 --uid-number=10001 --gid-number=10000 --login-shell=/bin/bash

echo "Конфигурирование утилиты веб-администрирования - phpLdapAdmin"
yum -y install phpldapadmin
cp -f $dir_config/phpldapadmin/config.php /etc/phpldapadmin/
cp -f $dir_config/phpldapadmin/phpldapadmin.conf /etc/httpd/conf.d/
systemctl restart httpd.service

#echo "Now manually set the group id and NIS domain using dsa.msc"
# Change passwords like this (on domain controller box)
#samba-tool user setpassword user1
#samba-tool fsmo show


echo "Проверка имени хостов и динамического обновления зоны DNS"
klist
host -t SRV _kerberos._udp.$DOMAIN.
host -t SRV _ldap._tcp.$DOMAIN.
host -t A $(hostname).

echo "$ADMINPASSWORD" | smbclient //localhost/netlogon -UAdministrator -c 'ls'
#echo "$ADMINPASSWORD" | kinit Administrator@$REALM
