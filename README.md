# Samba4-ActiveDirectory
Scripts and code for Active Directory integration

Scripts and their purpose
=========================
env_vars.sh
-----------
Set the variable values for the rest of the scripts.

functions.sh
------------
Functions for starting and stopping services using either
classic init style script commands or systemd equivalents.

setup_network.sh
----------------
Sets up the network config on a domain controller or member box.
Run this before any of the other scripts.

setup_samba.sh
--------------
Build, install and configure Samba4 as an Active Directory Domain Controller.
Note this script assumes you are running on a 192.168.0.x addressed LAN	

domain_controller_local_authentication.sh
-----------------------------------------
Run this on the domain controller to enable network logins on that box itself.

join_domain.sh
--------------
Run this on a domain member box to join it to the domain and enable network logins.

Links:
https://wiki.samba.org/index.php/Setting_up_Samba_as_an_Active_Directory_Domain_Controller
http://hpunix.org/cups/integracija-samba-i-active-directory.html
http://www.samba4.ru/?p=8
http://kolbosa.kz/samba4/
https://yvision.kz/post/542170

http://wiki.opennet.ru/Dhcp_%D0%B8_ad/samba4  //Вариант настройки DynDNS

https://wiki.samba.org/index.php/Setting_up_a_BIND_DNS_Server
https://wiki.samba.org/index.php/Managing_the_Samba_AD_DC_Service_Using_Systemd
https://wiki.samba.org/index.php/Joining_a_Samba_DC_to_an_Existing_Active_Directory //Про настройку smb.conf

https://github.com/myrjola/docker-samba-ad-dc/blob/master/init.sh //Настройка krb5 ktutil kerberos
http://blog.admindiary.com/  //Настройка окна авторизации при входе в ОС and настройка smb.conf with krb5 !!!!!

http://smb-conf.ru/1-smbconf-po-sekciyam.html

Troubleshooting:
https://wiki.samba.org/index.php/Updating_Samba#Notable_Enhancements_and_Changes