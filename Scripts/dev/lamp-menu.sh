#!/bin/bash
# LAMP menu...im a n00b

PS3='What option?: '
options=("httpd start" "httpd restart" "httpd status" "httpd stop" "httpd conf - vhosts" "php conf" "mariadb start" "mariadb restart" "mariadb status" "mariadb stop" "Quit")
select opt in "${options[@]}"
do
    case $opt in
    #httpd
        "httpd start")
            echo "Starting..."
            systemctl start httpd.service
            break           
            ;;
        "httpd restart")
            echo "Restarting..."
            systemctl restart httpd.service
            break
            ;;
        "httpd status")
            echo "Checking Status..."
            systemctl status httpd.service
            break
            ;;
        "httpd stop")
            echo "Stopping..."
            systemctl stop httpd.service
            break
            ;;
        "httpd conf - vhosts")
            echo "navigating to vhosts..."
            cd /etc/httpd
            $SHELL
            break
            ;;
        "php conf")
            echo "navigating to php..."
            cd /etc/php
            $SHELL
            break
            ;;
        #mariadb
        "mariadb start")
            echo "Starting..."
            systemctl start mariadb.service
            break           
            ;;
        "mariadb restart")
            echo "Restarting..."
            systemctl restart mariadb.service
            break
            ;;
        "mariadb status")
            echo "Checking Status..."
            systemctl status mariadb.service
            break
            ;;
        "mariadb stop")
            echo "Stopping..."
            systemctl stop mariadb.service
            break
            ;;
         "Quit")
            break
            ;;
        *) echo invalid option my guy...;;
    esac
done
