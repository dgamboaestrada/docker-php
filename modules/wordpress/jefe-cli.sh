#!/bin/bash
#
# wordpress jefe-cli.sh

# Load utilities
source ~/.jefe/libs/utilities.sh

# Configure environments vars of docker.
docker_env() {
    puts "Docker compose var env configuration." BLUE
    echo "" > .jefe/.env
    set_dotenv PROJECT_TYPE $project_type
    puts "Write project name (default $project_type):" MAGENTA
    read proyect_name
    if [ -z $proyect_name ]; then
        set_dotenv PROJECT_NAME $project_type
        proyect_name=$project_type
    else
        set_dotenv PROJECT_NAME $proyect_name
    fi
    puts "Write project root, directory path from your proyect (default src):" MAGENTA
    read option
    if [ -z $option ]; then
        set_dotenv PROJECT_ROOT "../src"
    else
        set_dotenv PROJECT_ROOT "../$option"
    fi
    puts "Write vhost (default $proyect_name.local):" MAGENTA
    read option
    if [ -z $option ]; then
        set_dotenv VHOST "$proyect_name.local"
    else
        set_dotenv VHOST $option
    fi
    puts "Write environment var name, (default local):" MAGENTA
    read option
    if [ -z $option ]; then
        set_dotenv ENVIRONMENT "local"
    else
        set_dotenv ENVIRONMENT "$option"
    fi
    puts "Write wordpress version, (default latest):" MAGENTA
    read option
    if [ -z $option ]; then
        set_dotenv WORDPRESS_VERSION "latest"
    else
        set_dotenv WORDPRESS_VERSION "$option"
    fi
    puts "Write wordpress table prefix (default wp_):" MAGENTA
    read option
    if [ -z $option ]; then
        set_dotenv WORDPRESS_TABLE_PREFIX "wp_"
    else
        set_dotenv WORDPRESS_TABLE_PREFIX $option
    fi
    puts "Database root password is password" YELLOW
    set_dotenv DB_ROOT_PASSWORD "password"
    puts "Database name is wordpress" YELLOW
    set_dotenv DB_NAME "wordpress"
    puts "Database user is wordpress" YELLOW
    set_dotenv DB_USER "wordpress"
    puts "Database wordpress password is wordpress" YELLOW
    set_dotenv DB_PASSWORD "wordpress"
    puts "phpMyAdmin url: localhost:8080" YELLOW
    set_dotenv PHPMYADMIN_PORT "8080"
    # Set nginx port to 80
    set_dotenv NGINX_PORT "80"
}

# Add vhost of /etc/hosts file
set_vhost(){
    if [ ! "$( grep jefe-cli_wordpress /etc/hosts )" ]; then
        puts "Setting vhost..." BLUE
        load_dotenv
        sudo sh -c "echo '127.0.0.1     $VHOST # ----- jefe-cli_$project_name' >> /etc/hosts"
        sudo sh -c "echo '127.0.0.1     phpmyadmin.$VHOST # ----- jefe-cli_$project_name' >> /etc/hosts"
        puts "Done." GREEN
    fi
}

# Create dump of the database of the proyect.
dump() {
    while getopts ":e:f:" option; do
        case "${option}" in
            e)
                e=${OPTARG}
                ;;
            f)
                f=${OPTARG}
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ -z "${e}" ]; then
        e="docker"
    fi

    if [ -z "${f}" ]; then
        f="dump.sql"
    fi

    load_dotenv
    if [[ "$e" == "docker" ]]; then
        docker exec -i ${project_name}_db mysqldump -u ${dbuser} -p"${dbpassword}" ${dbname}  > "./dumps/${f}"
    else
        load_settings_env $e
        ssh ${user}@${host} "mysqldump -u${dbuser} -p\"${dbpassword}\" ${dbname} --host=${dbhost} > ./dumps/${f}"
    fi
}

# Import dump of dumps folder of the proyect.
import_dump() {
    usage= cat <<EOF
up [-e] [--environment] [-f] [--file] [-h] [--help]

Arguments:
    -e, --environment		Set environment to import dump
    -f, --file			File name of dump to import (default: dump.sql)
    -h, --help			Print Help (this message) and exit
EOF
    # set an initial value for the flag
    ENVIRONMENT="docker"
    FILE_NAME="dump.sql"

    # read the options
    OPTS=`getopt -o e:f:h --long environment:,file:,help -n 'jefe' -- "$@"`
    if [ $? != 0 ]; then puts "Invalid options." RED; exit 1; fi
    eval set -- "$OPTS"

    # extract options and their arguments into variables.
    while true ; do
        case "$1" in
            -e|--environment) ENVIRONMENT=$2 ; shift 2 ;;
            -f|--file) FILE_NAME=$2 ; shift 2 ;;
            -h|--help) echo $usage ; exit 1 ; shift ;;
            --) shift ; break ;;
            *) echo "Internal error!" ; exit 1 ;;
        esac
    done

    load_dotenv
    if [[ "$ENVIRONMENT" == "docker" ]]; then
        docker exec -i $db_{project_name} mysql -u ${dbuser} -p"${dbpassword}" ${dbname}  < "./dumps/${FILE_NAME}"
    else
        load_settings_env $ENVIRONMENT
        ssh ${user}@${host} "mysql -u${dbuser} -p\"${dbpassword}\" ${dbname} --host=${dbhost} < ./dumps/${FILE_NAME}"
    fi
}

# Delete database and create empty database.
resetdb() {
    while getopts ":e:" option; do
        case "${option}" in
            e)
                e=${OPTARG}
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ -z "${e}" ]; then
        e="docker"
    fi

    if [[ "$e" == "docker" ]]; then
        load_dotenv
        docker exec -i ${project_name}_db mysql -u"${dbuser}" -p"${dbpassword}" -e "DROP DATABASE IF EXISTS ${dbname}; CREATE DATABASE ${dbname}"
    else
        load_settings_env $e
        ssh ${user}@${host} "mysql -u${dbuser} -p\"${dbpassword}\" ${dbname} --host=${dbhost} -e \"DROP DATABASE IF EXISTS ${dbname}; CREATE DATABASE ${dbname}\""
    fi
}

# Synchronize files to the selected environment.
deploy() {
    usage= cat <<EOF
ps [-e <environment>] [--environment <environment>] [-t] [--test] [-h] [--help]

Arguments:
    -e, --environment		Set environment to deployed
    -t, --test			Perform a test of the files to be synchronized
    -h, --help			Print Help (this message) and exit
EOF
    # set an initial value for the flag
    ENVIRONMENT=""
    TEST=false

    # read the options
    OPTS=`getopt -o e:th --long environment:,test,help -n 'jefe' -- "$@"`
    if [ $? != 0 ]; then puts "Invalid options." RED; exit 1; fi
    eval set -- "$OPTS"

    # extract options and their arguments into variables.
    while true ; do
        case "$1" in
            -e|--environment) ENVIRONMENT=$2 ; shift 2 ;;
            -t|--test) TEST=true ; shift ;;
            -h|--help) echo $usage ; exit 1 ; shift ;;
            --) shift ; break ;;
            *) echo "Internal error!" ; exit 1 ;;
        esac
    done

    load_dotenv
    load_settings_env $ENVIRONMENT
    excludes=$( echo $exclude | sed -e "s/;/ --exclude=/g" )
    cd .jefe
    if ! $TEST; then
        set -x #verbose on
        rsync -az --force --delete --progress --exclude="uploads/" --exclude="upgrade/" --exclude=$excludes -e "ssh -p$port" "$project_root/." "${user}@${host}:$public_dir"
        set +x #verbose off
    else
        set -v #verbose on
        rsync --dry-run -az --force --delete --progress --exclude="uploads/" --exclude="upgrade/" --exclude=$excludes -e "ssh -p${port}" "$project_root/." "${user}@${host}:$public_dir"
        set +v #verbose off
    fi
    cd ..
}

# Execute the command "composer install" in workdir folder.
composer_install() {
    e=$1
    if [ -z "${e}" ]; then
        e="docker"
    fi
    if [[ "$e" == "docker" ]]; then
        load_dotenv
        docker exec -it ${project_name}_php bash -c 'composer install'
    else
        load_settings_env $e
        ssh ${user}@${host} -p $port "cd ${public_dir}/; composer install"
    fi
}

# Execute the command "composer update" in workdir folder.
composer_update() {
    e=$1
    if [ -z "${e}" ]; then
        e="docker"
    fi
    if [[ "$e" == "docker" ]]; then
        load_dotenv
        docker exec -it ${project_name}_php bash -c 'composer update'
    else
        load_settings_env $e
        ssh ${user}@${host} -p $port "cd ${public_dir}/; composer update"
    fi
}
