#!/usr/bin/env bash
set -e
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin


full_domain=blog.yanyong.cc
new_user=yong
ssh_port=2444
debian_mirror=http://ftp.us.debian.org/debian/
debian_security=http://security.debian.org/debian-security
ntp_servers='0.us.pool.ntp.org 1.us.pool.ntp.org 2.us.pool.ntp.org 3.us.pool.ntp.org'
password16=`tr -dc '[:alnum:]' < /dev/urandom | head -c 16`
password8=`tr -dc '[:digit:][:lower:]' < /dev/urandom | head -c 8`


global_variables(){
    _fqdn="$full_domain"
    _user="$new_user"
    _ssh_port="$ssh_port"
    _hostname=${_fqdn%%.*}
    _ip=`hostname -I | awk '{print $1}'`
    _source="$debian_mirror"
    _source_security="$debian_security"
    _ntp="$ntp_servers"
    _password="$password16"
    _passwd_rsa="$password8"
}

updateOS(){
    if [[ ! -f /etc/apt/sources.list.bak ]]; then cp /etc/apt/sources.list{,.bak}; fi
    cat > /etc/apt/sources.list <<- EOF
deb $_source buster main
deb-src $_source  buster main
deb $_source_security buster/updates main
deb-src $_source_security buster/updates main
deb $_source buster-updates main
deb-src $_source buster-updates main
EOF
    apt-get update && apt-get -y upgrade
    apt-get -y install man sudo vim net-tools
}

set_hostname(){
    hostname $_hostname
    echo $_hostname > /etc/hostname
    if ! grep -q "$_ip $_fqdn $_hostname" /etc/hosts; then
        echo "$_ip $_fqdn $_hostname" >> /etc/hosts
    fi
}

set_profile(){
cat > /etc/profile.d/${_fqdn}.sh <<- EOF
export HISTFILESIZE=20000
export HISTTIMEFORMAT="%F %T"
export HISTCONTROL="ignoreboth" 
alias ls='ls --color=auto'
alias ll='ls -l --color=auto'
alias lt='ls -alt --color=auto'
alias grep='grep --color=auto'
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'
umask 022
export TMOUT=3600
EOF
}

set_timezone(){
    timedatectl set-timezone Asia/Shanghai
    sed -ri 's/^#(NTP=)$/\1'"$_ntp"'/' /etc/systemd/timesyncd.conf
    systemctl restart systemd-timesyncd
}

create_user(){
    iscreate=false
    if ! id -u $_user &> /dev/null; then
        iscreate=true
        useradd -m $_user -s /bin/bash
        eval chpasswd <<< "$_user:$_password"
        usermod -aG sudo $_user
        echo -e '%sudo\tALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/nopasswd
        mkdir /home/$_user/.ssh
        chown $_user:$_user /home/$_user/.ssh
        chmod 700 /home/$_user/.ssh
        su - $_user -c "ssh-keygen -qf /home/$_user/.ssh/id_rsa.${_user} -t rsa -N $_passwd_rsa"
        cat /home/$_user/.ssh/id_rsa.$_user.pub > /home/$_user/.ssh/authorized_keys
        chown $_user:$_user /home/$_user/.ssh/authorized_keys
        chmod 600 /home/$_user/.ssh/authorized_keys
    else
        echo "$_user exist!(exit status 2)" && exit 2
    fi
}

set_ssh(){
    if [[ ! -f /etc/ssh/sshd_config.bak ]]; then cp /etc/ssh/sshd_config{,.bak}; fi

    if grep -Eq '^PermitRootLogin (yes|no)$' /etc/ssh/sshd_config; then
        sed -ri -e 's/^(PermitRootLogin )yes$/\1no/' /etc/ssh/sshd_config
    else
        echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
    fi

    if grep -Eq '^PasswordAuthentication (yes|no)$' /etc/ssh/sshd_config; then
        sed -ri -e 's/^(PasswordAuthentication )yes$/\1no/' /etc/ssh/sshd_config
    else
        echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
    fi

    if grep -q '^Port [0-9]\+' /etc/ssh/sshd_config; then
        sed -ri 's/^Port [0-9]+/Port '"$_ssh_port"'/' /etc/ssh/sshd_config
    else
        echo "Port $_ssh_port" >> /etc/ssh/sshd_config
    fi 
    systemctl reload ssh
}

set_iptables(){
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -p icmp -m state --state NEW --icmp-type echo-request -j ACCEPT
    iptables -A INPUT -p tcp -m state --state NEW -m multiport --dports "$_ssh_port",http,https -j ACCEPT
    iptables -P INPUT DROP

    echo 'iptables-persistent iptables-persistent/autosave_v4 boolean true' | debconf-set-selections
    echo 'iptables-persistent iptables-persistent/autosave_v6 boolean false' | debconf-set-selections
    apt-get -y install iptables-persistent
    netfilter-persistent save
    if [[ ! -f /etc/iptables/rules.v4.bak ]]; then cp /etc/iptables/rules.v4{,.bak}; fi
    sed -ri 's/#?set_iptables$/#set_iptables/' $0  # once_exec
}

print_info(){
  if $iscreate; then
    echo ">>>> /root/${0}.log"
    cat >> /root/${0}.log <<- EOF
**********************************************************************
User name: $_user
User password: $_password
SSH port: $_ssh_port
private key(id_rsa.$_user):
$(cat /home/$_user/.ssh/id_rsa.$_user)
password(id_rsa.$_user): $_passwd_rsa
**********************************************************************

EOF
    chmod 400 /root/${0}.log
    str=`cat /root/${0}.log`
    echo -e "\033[31m${str}\033[0m"
  fi
}

main(){
    global_variables
    updateOS
    set_hostname
    set_profile
    set_timezone
    create_user
    set_ssh
    set_iptables
    print_info
}

main
