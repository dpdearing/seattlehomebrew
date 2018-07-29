#!/bin/sh
MARIADB=10.3.8
WORDPRESS=4.9.7

DB_CONTAINER=mariadb
WP_CONTAINER=seattlehomebrew-wp

if [ -z "$1" ]; then
	TIMESTAMP=$(date +%Y-%m-%d-%H%M)
	WP_FILE="${TIMESTAMP}_backup_seattlehomebrew_wp.tar.gz"
	DB_FILE="${TIMESTAMP}_backup_seattlehomebrew_wp_mariadb.sql.gz"

	echo "\tNo backup file specified; Creating seattlehomebrew backups with timestamp $TIMESTAMP"

	# Check if the containers exist
	if [ ! "$(docker ps -a | grep $DB_CONTAINER)" ]; then
		echo "\tThe mariadb docker container '$DB_CONTAINER' does not exist."
	fi
	if [ ! "$(docker ps -a | grep $WP_CONTAINER)" ]; then
		echo "\tThe wordpress docker container '$WP_CONTAINER' does not exist."
	fi
	if [ ! "$(docker ps -a | grep $DB_CONTAINER)" ] || [ ! "$(docker ps -a | grep $WP_CONTAINER)" ]; then
		echo "\tNo backup created!"
		exit 1
	else
		echo "\tBacking up $WP_CONTAINER container..."
		# connect to seattlehomebrew-data data volume and tar everything in /var/www/html
		docker run --rm --volumes-from $WP_CONTAINER -v $PWD:/backups ubuntu tar cfz /backups/${WP_FILE} -C /var/www/html .

		echo "\tBacking up wp_seattlehomebrew from $DB_CONTAINER container..."
		# connect to mariadb database and dump everything in wp_seattlehomebrew
		docker run --rm -it -u root -v $PWD:/backups --link $DB_CONTAINER:mysql mariadb:$MARIADB sh -c 'exec mysqldump -h"$MYSQL_PORT_3306_TCP_ADDR" -P"$MYSQL_PORT_3306_TCP_PORT" -uroot -p"$MYSQL_ENV_MYSQL_ROOT_PASSWORD" --databases wp_seattlehomebrew | gzip -c | cat > /backups/'${DB_FILE}

		echo
		echo "\tCreated seattlehomebrew  mariadb  backup at $PWD/$DB_FILE"
		echo "\tCreated seattlehomebrew wordpress backup at $PWD/$WP_FILE"
		echo
	fi

else
	TIMESTAMP=${1}
	TIMESTAMP=${TIMESTAMP%%_*} # everything before the last underscore
	TIMESTAMP=${TIMESTAMP##*/} # everything after the last forward slash
	WP_FILE="${TIMESTAMP}_backup_seattlehomebrew_wp.tar.gz"
	DB_FILE="${TIMESTAMP}_backup_seattlehomebrew_wp_mariadb.sql.gz"

	echo
	echo "\tRestoring seattlehomebrew from backup files with timestamp '$TIMESTAMP'"

	if [ ! -e $DB_FILE ]; then
		echo "\tThe  mariadb  backup file '$DB_FILE' does not exist."
	fi
	if [ ! -e $WP_FILE ]; then
		echo "\tThe wordpress backup file '$WP_FILE' does not exist."
	fi
	if [ ! -e $WP_FILE ] || [ ! -e $DB_FILE ]; then
		echo "\tRestore aborted."
		echo
		exit 1
	else

		# Conifgure 1G swap space if not already done
		if [ ! -f /swapfile ]; then
			echo "\tConfiguring swap space"
			echo
			# Based on https://www.digitalocean.com/community/tutorials/how-to-add-swap-space-on-ubuntu-16-04
			sudo fallocate -l 1G /swapfile
			sudo chmod 600 /swapfile
			sudo mkswap /swapfile
			sudo swapon /swapfile
			echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
		fi

		echo
		echo "\tRestoring seattlehomebrew  mariadb  backup from $DB_FILE"
		echo

		docker pull mariadb:$MARIADB
		# create mariadb data volume; no error if it already exists
		docker volume create mariadb

		# start mariadb container
		docker run --name mariadb -v $DB_CONTAINER:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=tour -d mariadb:$MARIADB
		echo "\t ...waiting 15 seconds for mariadb container to initialize..."
		sleep 15s

		# restore mysql dump file, which should specify the database name
		docker run -it --rm -v $(pwd):/backups --link $DB_CONTAINER:mysql mariadb:$MARIADB sh -c 'exec zcat '"/backups/$DB_FILE"' | mysql -h"$MYSQL_PORT_3306_TCP_ADDR" -P"$MYSQL_PORT_3306_TCP_PORT" -uroot -p"$MYSQL_ENV_MYSQL_ROOT_PASSWORD"'
		echo "\tmariadb backup restored"


		echo
		echo "\tRestoring seattlehomebrew wordpress backup from $WP_FILE"
		echo

		docker pull wordpress:$WORDPRESS
		docker volume create seattlehomebrew-data

		# restore wordpress backup data (/var/www/html) to seattlehomebrew-data data volume
		docker run --rm -v seattlehomebrew-data:/var/www/html -v $(pwd):/backups ubuntu sh -c "tar xfz /backups/$WP_FILE -C /var/www/html"

		# start wordpress container
		docker run --name $WP_CONTAINER -v seattlehomebrew-data:/var/www/html --link mariadb:mysql -e WORDPRESS_DB_NAME=wp_seattlehomebrew -p 80:80 -d wordpress:$WORDPRESS
		echo "\twordpress backup restored"

		echo "\tRestore complete."
	fi
fi
