#!/usr/bin/env bash
set -e
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin


full_domain=www.hisport.cloud
new_user=pengjl
ssh_port=21622
# https://mirrors.ustc.edu.cn/help/centos.html
centos_repo=http://mirrors.aliyun.com/repo/Centos-8.repo
password16=`tr -dc '[:alnum:]' < /dev/urandom | head -c 16`
password8=`tr -dc '[:digit:][:lower:]' < /dev/urandom | head -c 8`


global_variables(){
    _fqdn="$full_domain"
    _user="$new_user"
    _ssh_port="$ssh_port"
    _hostname=${_fqdn%%.*}
    _ip=`hostname -I | awk '{print $1}'`
    _repo="$centos_repo"
    _ntp="$ntp_pool"
    _password="$password16"
    _passwd_rsa="$password8"
}

updateOS(){
    if [[ ! -f /etc/yum.repos.d/CentOS-Linux-BaseOS.repo.bak ]]; then cp /etc/yum.repos.d/CentOS-Linux-BaseOS.repo{,.bak}; fi
    curl -o /etc/yum.repos.d/CentOS-Linux-BaseOS.repo $_repo || wget -O /etc/yum.repos.d/CentOS-Linux-BaseOS.repo $_repo

    if [[ ! -f /etc/yum.repos.d/CentOS-Linux-AppStream.repo.bak ]]; then cp /etc/yum.repos.d/CentOS-Linux-AppStream.repo{,.bak}; fi
    sed -i 's/enabled=1/enabled=0/' /etc/yum.repos.d/CentOS-Linux-AppStream.repo

    setenforce 0 || true
    sed -i 's/SELINUX=enforcing\|SELINUX=permissive/SELINUX=disabled/' /etc/selinux/config

    yum clean all
    yum -y update
    yum -y install epel-release vim net-tools
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
alias lt='ls -alt --color=auto'
umask 022
export TMOUT=3600
EOF
}

set_timezone(){
    timedatectl set-timezone Asia/Shanghai
    systemctl restart chronyd
    systemctl enable chronyd
    chronyc -a makestep
}

create_user(){
    iscreate=false
    if ! id -u $_user &> /dev/null; then
        iscreate=true
        useradd -m $_user -s /bin/bash
        eval chpasswd <<< "$_user:$_password"
        echo -e "$_user\tALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/nopasswd
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

set_sshd(){
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
    systemctl reload sshd
}

set_firewall-cmd(){
    firewall-cmd --zone=public --add-port=${_ssh_port}/tcp --permanent
    firewall-cmd --zone=public --add-port=80/tcp --add-port=443/tcp --permanent
    firewall-cmd --reload
    sed -ri 's/#?set_firewall-cmd$/#set_firewall-cmd/' $0  # once_exec
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
    set_sshd
    set_firewall-cmd
    print_info
}

main
