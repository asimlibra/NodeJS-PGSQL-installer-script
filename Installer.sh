#!/bin/bash

set -e
set -o pipefail
printf "\033c"

## Must be run as root, or with sudo
if (( $EUID != 0 )); then
    echo "Please run this script as root, or even better: use sudo."
    exit 1
fi

setUser(){
	# Set password of System user created as $sys_user
	read -p "Enter UserName for the Deployment [deployuser]: " sys_user
	sys_user=${sys_user:-deployuser}
	echo "Enter the password that $sys_user user will have."
	while true; do
		read -s -p $'\n'"Password: " user_pass
		read -s -p $'\n'"Type password again: " user_pass2
		[ "$user_pass" = "$user_pass2" ] && break
		echo -e "\nError, please try again"
	done
		echo -e "\n\e[92mSucess!!\e[0m"
}

#Installing NVM, NodeJS, and Angular/cli against user $sys_user
Installnode(){
	read -p "Enter version for Node: " node_ver
	read -p "Enter angular Cli version [@angular/cli]: " angular_ver
	angular_ver=${angular_ver:-@angular/cli}
	getent passwd | grep ^${sys_user}: || useradd --system --shell $(which bash) --create-home ${sys_user} --password ${user_pass}
	su - ${sys_user} -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.2/install.sh | bash"
#	su - ${sys_user} -c "source ~/.nvm/nvm.sh && nvm --version"
  su - ${sys_user} -c "source ~/.nvm/nvm.sh && nvm install ${node_ver}"
  su - ${sys_user} -c "source ~/.nvm/nvm.sh && nvm alias default ${node_ver}"
	su - ${sys_user} -c "source ~/.nvm/nvm.sh && npm install --silent --save-dev ${angular_ver}"

	}

setPsqlUser(){
	# Set PostgreSQL user name
	read -p "Enter PostgreSQL verion: [i.e: 10, 11]: " version
 	read -p "Enter the PostgreSQL user name [eondash]: " psql_user
	psql_user=${psql_user:-eondash}
}

setPsqlPassword(){
	# Set password of PostgreSQL's $psql_user user
	echo "Enter the password that the PostgreSQL's $psql_user user will have."
	while true; do
		read -s -p $'\n'"Password: " psql_pass
		read -s -p $'\n'"Type password again: " psql_pass2
		[ "$psql_pass" = "$psql_pass2" ] && break
		echo -e "\nError, please try again"
	done
	echo -e "\n\e[92mSucess!!\e[0m"
}

setPsqlDbName(){
	# Set PostgreSQL database name
	read -p "Enter the PostgreSQL database name [eondash]: " psql_db_name
	psql_db_name=${psql_db_name:-eondash}
}

installCentos(){
	# Detect SElinux status
	SELINUXSTATUS=$(getenforce)
	if [ "$SELINUXSTATUS" == "Enforcing" ]; then
		echo "SElinux is set as Enforcing, disable it or adjust your configuration"
		read -p "Would you like to change it to permissive? " ans
		case "$ans" in
			[yY]|[yY][eE][sS])
				sed -i s/^SELINUX=.*$/SELINUX=permissive/ /etc/sysconfig/selinux
				setenforce 0 && echo -e "\n\e[92mSucess!!\e[0m"
				;;
			*)
				read -n 1 -s -r -p "Press any key to continue"
				;;
		esac
		echo -e "\n"
	fi

	# Adding repositories
	yum -y groupinstall 'Development Tools'
	rpm -Uvh https://yum.postgresql.org/$version/redhat/rhel-7-x86_64/pgdg-centos$version-$version-2.noarch.rpm

	# Installing PostgreSQL

	yum -y install postgresql$version-contrib postgresql$version-server

	/usr/pgsql-$version/bin/postgresql-$version-setup initdb
	systemctl start postgresql-$version.service; systemctl enable postgresql-$version.service

	cd /var/lib
#Setting up postgres role and database
	sudo -u postgres psql <<EOF
		create user "$psql_user" with password '$psql_pass';
		create database "$psql_db_name" with owner "$psql_user";
		GRANT ALL PRIVILEGES ON DATABASE "$psql_db_name" TO "$psql_user";
EOF
#Changing authentication menthod from ident to md5, and listen address from localhost to global

	sed -r -i "s|(^local\s*all\s*all\s*)peer$|\1trust|g" /var/lib/pgsql/$version/data/pg_hba.conf
	sed -r -i "s|(^host\s*all\s*all\s*127.0.0.1/32\s*)ident$|\1md5|g" /var/lib/pgsql/$version/data/pg_hba.conf
	sed -r -i "s|(^host\s*all\s*all\s*::1/128\s*)ident$|\1md5|g" /var/lib/pgsql/$version/data/pg_hba.conf

	systemctl restart postgresql-$version.service

}

installDebianBased() {
	# Adding repositories
	wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O- | apt-key add -
	echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | tee /etc/apt/sources.list.d/postgresql.list
	apt-get update -y


	# Installing PostgreSQL
	apt-get install -y build-essential postgresql-$version

	cd /var/lib/postgresql/
	systemctl start postgresql; systemctl enable postgresql
	sudo -u postgres psql <<EOF
		create user "$psql_user" with password '$psql_pass';
		create database "$psql_db_name" with owner "$psql_user";
		GRANT ALL PRIVILEGES ON DATABASE "$psql_db_name" TO "$psql_user";
EOF

#Changing authentication menthod from ident to md5, and listen address from localhost to global
sed -r -i "s|(^local\s*all\s*all\s*)peer$|\1trust|g" /etc/postgresql/$version/main/pg_hba.conf
sed -r -i "s|(^host\s*all\s*all\s*127.0.0.1/32\s*)ident$|\1md5|g" /etc/postgresql/$version/main/pg_hba.conf
sed -r -i "s|(^host\s*all\s*all\s*::1/128\s*)ident$|\1md5|g" /etc/postgresql/$version/main/pg_hba.conf
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/postgresql/$version/main/postgresql.conf
}


# Ensure distribution is compatible
if [ ! -f /etc/os-release ]
then
        echo "Distribution not supported"
        exit 1
fi

# Detect distribution
source /etc/os-release
setUser
Installnode
setPsqlUser
setPsqlPassword
setPsqlDbName
case $ID in
	centos)
		installCentos
		;;
	debian|ubuntu)
		installDebianBased
		;;
	*)
		echo "Distribution $ID is currently not supported."
		exit 1
		;;
esac

echo "~~~~~~~~~~~~~~~************~~~~~~~~~~~~~~~~~"
echo "~~~~~~~~~~~~~~~  FINISHED  ~~~~~~~~~~~~~~~~~"
echo "~~~~~~~~~~~~~~~************~~~~~~~~~~~~~~~~~"

exit 0
