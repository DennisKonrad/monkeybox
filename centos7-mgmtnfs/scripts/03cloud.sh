set -exu

# KVM and CloudStack agent dependencies
yum install -y ntp python-argparse net-tools ebtables ethtool iproute ipset iptables openssh-clients perl qemu-img libuuid glibc nss-softokn-freebl wget

# Management server dependecies and database
wget https://downloads.mariadb.com/MariaDB/mariadb_repo_setup
chmod +x mariadb_repo_setup
sudo ./mariadb_repo_setup
yum install -y mariadb-server nfs-utils mysql-connector-java genisoimage
systemctl enable mariadb

# Marvin tests dependencies
yum install -y python-pip pyOpenSSL telnet tcpdump zlib-devel bzip2-devel openssl-devel xz-libs rsync sqlite sqlite-devel python-paramiko python-setuptools python-devel mysql-devel openssl-devel ncurses-devel libxslt-devel libffi-devel openssh-askpass jq mariadb git screen sshpass at vim tmux mysql-connector-python gcc gcc-c++ make patch autoconf automake binutils
pip install pycrypto texttable

# CloudStack Development Tools
yum install -y openjdk-8-jdk maven python-mysql.connector libmysql-java mysql-server mysql-client bzip2 nfs-common uuid-runtime python-setuptools ipmitool genisoimage nfs-kernel-server quota

# There are definitely some java versions installed that are too much now. Java 11 seems the way to go for the future
yum install -y java-11-openjdk-devel java-11-openjdk java-11-openjdk-headless yum-utils
SET_JAVA_PATH=$(repoquery -l java-11-openjdk-headless | grep x86_64 | grep '/bin/java')
alternatives --set java ${SET_JAVA_PATH}

SET_JAVAC_PATH=$(repoquery -l java-11-openjdk-devel | grep x86_64 | grep '/bin/javac')
alternatives --set javac ${SET_JAVAC_PATH}

# Create NFS export
echo "/export  *(rw,async,no_root_squash,no_subtree_check)" > /etc/exports
mkdir -p /export/testing/primary /export/testing/secondary
systemctl enable nfs-server
systemctl start nfs-server

# Install cloudmonkey
wget -O /bin/cmk https://github.com/apache/cloudstack-cloudmonkey/releases/download/6.0.0/cmk.linux.x86-64
chmod +x /bin/cmk

# Fix SELinux
setenforce 0
sed -i 's/SELINUX=.*/SELINUX=permissive/g' /etc/selinux/config

# Fix MySQL
sed -i "/\[mysqld\]/a innodb_rollback_on_timeout=1" /etc/my.cnf
sed -i "/\[mysqld\]/a innodb_lock_wait_timeout=600" /etc/my.cnf
sed -i "/\[mysqld\]/a max_connections=700" /etc/my.cnf
sed -i "/\[mysqld\]/a log-bin=mysql-bin" /etc/my.cnf
sed -i "/\[mysqld\]/a binlog-format = 'ROW'" /etc/my.cnf

# TODO i think we do not need these
# Marvin tests dependencies
#yum install -y python-pip pyOpenSSL telnet tcpdump zlib-devel bzip2-devel openssl-devel xz-libs wget sqlite sqlite-devel python-paramiko python-setuptools python-devel mysql-devel openssl-devel ncurses-devel libxslt-devel libffi-devel openssh-askpass jq mariadb git screen sshpass at vim tmux mysql-connector-python gcc gcc-c++ make patch autoconf automake binutils
#pip install pycrypto texttable

# Setup networking
cat > /etc/sysconfig/network-scripts/ifcfg-eth0 <<EOF
TYPE=Ethernet
DEVICE=eth0
ONBOOT=yes
BOOTPROTO=static
IPADDR=172.20.1.2
NETMASK=255.255.0.0
GATEWAY=172.20.0.1
DNS1=8.8.8.8
DNS2=8.8.4.4
NM_CONTROLLED=no
EOF

# Setup nat for agent via qemu hook
mkdir -p /etc/libvirt/hooks/
touch /etc/libvirt/hooks/qemu
cat > /etc/libvirt/hooks/qemu <<'EOF'
#!/bin/bash
# used some from advanced script to have multiple ports: use an equal number of guest and host ports

echo `date` hook/qemu "${1}" "${2}" >>/root/hook.log

### some router 
#Guest_name=master-centos7-kvm1
Guest_ipaddr=172.20.1.2
Host_port=(  '8001' )
Guest_port=( '8000' )


length=$(( ${#Host_port[@]} - 1 ))
if [ "${1}" = "${Guest_name}" ]; then
	if [ "${2}" = "stopped" ] || [ "${2}" = "reconnect" ]; then
	    for i in `seq 0 $length`; do
		    echo "Stopped $Guest_name. Cleaning iptables" >>/root/hook.log
		    /sbin/iptables -D FORWARD -o virbr1 -d  ${Guest_ipaddr} -j ACCEPT
		    /sbin/iptables -t nat -D PREROUTING -p tcp --dport ${Host_port[$i]} -j DNAT --to ${Guest_ipaddr}:${Guest_port[$i]}
	    done
	fi
	if [ "${2}" = "start" ] || [ "${2}" = "reconnect" ]; then
	    for i in `seq 0 $length`; do
		    echo "Stopped $Guest_name. Adding rules to iptables" >>/root/hook.log
		    /sbin/iptables -I FORWARD -o virbr1 -d  ${Guest_ipaddr} -j ACCEPT
		    /sbin/iptables -t nat -I PREROUTING -p tcp --dport ${Host_port[$i]} -j DNAT --to ${Guest_ipaddr}:${Guest_port[$i]}
	    done
	fi
fi
EOF
chmod +x /etc/libvirt/hooks/qemu

# TODO FixME
systemctl disable firewalld

# Setup iptables
iptables -I INPUT -p tcp -m tcp --dport 8000 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 8080 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 8096 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 8250 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 8787 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 22 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 1798 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 16509 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 16514 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 5900:6100 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 49152:49216 -j ACCEPT
iptables-save > /etc/sysconfig/iptables
