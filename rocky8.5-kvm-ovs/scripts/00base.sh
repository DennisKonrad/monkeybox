set -eux

yum -y update

cat > /etc/motd << EOF

   __?.o/  AlmaLinux 8.4 KVM MonkeyBox
  (  )#    Built from https://github.com/DennisKonrad/monkeybox
 (___(_)   Happy CloudStack hacking!

EOF

# Essentials
yum install -y tmux vim wget jq

# Fix hostname to get from dhcp, otherwise use localhost
hostnamectl set-hostname localhost --static
