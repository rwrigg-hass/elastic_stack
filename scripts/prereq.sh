#!/bin/bash

if [[ -z $SUDO_USER || $SUDO_USER == "root" ]] ;then
  echo "Must sudo as desired Elastic_Stack service user" 
  exit
fi

DIST=`lsb_release -si`
VERSION=`lsb_release -sr`

pkginstall () {
  if [ $DIST = "Ubuntu" ] ;then
    if [ $(dpkg-query -W -f='${Status}' $1 2>/dev/null | grep -c "ok installed") -eq 0 ] ;then
        echo "Installing $1"
        apt install -y $1
      else
        echo "$1 is already installed"	  
	fi
  elif [ $DIST = "RedHatEnterpriseServer" ] ;then
    yum install -y $1
  fi
}

if [ $DIST = "Ubuntu" ] ;then
  PKGMGR="apt"
  if [ $VERSION = "18.04" ]; then
    DOCKER="docker-ce"
  else
    DOCKER="docker-ce"
  fi
elif [ $DIST = "RedHatEnterpriseServer" ] ;then
  if [[ $VERSION =~ ^7\. ]] ;then
    PKGMGR="yum"
    DOCKER="docker-ce"
  else
    echo "Unsupport Red Hat Enterprise Linux Release"
	exit
  fi
else
  echo "Unsupported Distribution"
  exit
fi

${PKGMGR} update
pkginstall git
pkginstall curl

if [ ! -d /opt/elastic_stack ];
then
  echo "Cloning elastic_stack repo"
  cd /opt
  git clone https://github.com/HASecuritySolutions/elastic_stack.git
  chown -R ${SUDO_USER} /opt/elastic_stack
fi

if [ $DIST = "Ubuntu" ] ;then
  if grep -q 'deb \[arch=amd64\] https://download.docker.com/linux/ubuntu' /etc/apt/sources.list
  then
    echo "Docker software repository is already installed"
  else
    echo "Docker software repository is not installed. Installing"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update
    if grep -q 'deb \[arch=amd64\] https://download.docker.com/linux/ubuntu' /etc/apt/sources.list
    then
      echo "Docker software repository is now installed"
    fi
  fi
elif [ $DIST = "RedHatEnterpriseServer" ] ;then
  pkginstall yum-utils
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
fi

if [ $DIST = "RedHatEnterpriseServer" ] ;then
  yum erase -y docker docker-common docker-io
fi

pkginstall $DOCKER

if [ $DIST = "RedHatEnterpriseServer" ] ;then
  systemctl enable docker
  systemctl start docker
fi

if grep docker /etc/group | grep -q ${SUDO_USER}
then
  echo "${SUDO_USER} user already member of docker group"
else
  echo "Adding ${SUDO_USER} user to docker group"
  sudo usermod -aG docker ${SUDO_USER}
fi

if [ -f /usr/local/bin/docker-compose ];
then
  echo "Docker Compose is already installed"
else
  echo "Installing Docker Compose"
  sudo curl -L https://github.com/docker/compose/releases/download/1.19.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
fi

if [ $DIST = "Ubuntu" ] ;then
  if grep -q 'vm.max_map_count' /etc/sysctl.conf
  then
    echo "VM Max Map Count already configured"
  else
    echo "Setting vm.max_map_count to 262144"
    sudo sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
  fi
elif [ $DIST = "RedHatEnterpriseServer" ] ;then
  echo "Setting vm.max_map_count to 262144"
  echo "vm.max_map_count=262144" > /etc/sysctl.d/99-elastic_stack.conf
  sysctl --load /etc/sysctl.d/99-elastic_stack.conf
fi
