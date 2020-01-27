set -exu

# KVM and CloudStack agent dependencies
yum install -y ntp java-1.8.0-openjdk-headless.x86_64 python-argparse python-netaddr net-tools bridge-utils ebtables ethtool iproute ipset iptables libvirt libvirt-python openssh-clients perl qemu-img qemu-kvm libuuid glibc nss-softokn-freebl

# Management server dependecies and services
yum install -y mariadb-server nfs-utils mysql-connector-java genisoimage
systemctl disable mariadb

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

# Marvin tests dependencies
yum install -y python-pip pyOpenSSL telnet tcpdump zlib-devel bzip2-devel openssl-devel xz-libs wget sqlite sqlite-devel python-paramiko python-setuptools python-devel mysql-devel openssl-devel ncurses-devel libxslt-devel libffi-devel openssh-askpass jq mariadb git screen sshpass at vim tmux mysql-connector-python gcc gcc-c++ make patch autoconf automake binutils
pip install pycrypto texttable

# Setup networking
cat > /etc/sysconfig/network-scripts/ifcfg-eth0 <<EOF
TYPE=Ethernet
DEVICE=eth0
ONBOOT=yes
BOOTPROTO=static
BRIDGE=cloudbr0
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
Guest_ipaddr=172.20.1.10
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

# Setup iptables
iptables -I INPUT -p tcp -m tcp --dport 8000 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 8080 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 8096 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 8787 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 22 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 1798 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 16509 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 16514 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 5900:6100 -j ACCEPT
iptables -I INPUT -p tcp -m tcp --dport 49152:49216 -j ACCEPT
iptables-save > /etc/sysconfig/iptables