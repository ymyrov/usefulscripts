#/bin/bash

RED='\033[0;31m'
NC='\033[0m' # No Color
GREEN='\033[0;32m'
BLUE='\033[0;34m'
GRAY='\033[0;37m'
BR_NAME=$1  #`pwd |cut -d'/' -f4`
WS_CONT=`docker ps |grep laradock_workspace | awk '{ print $1 }'`
DB_CONT=`docker ps |grep laradock_postgres  | awk '{ print $1 }'`
NGINX_CONT=`docker ps |grep laradock_nginx  | awk '{ print $1 }'`
DB_KEY=POSTGRES_DB
DB_VALUE=$BR_NAME
ENV_FILE=/var/www/$BR_NAME/laradock/.env
LARA_PATH=/opt/deploy
cp $LARA_PATH/$BR_NAME/laradock/env-example $LARA_PATH/$BR_NAME/laradock/.env
cp $LARA_PATH/$BR_NAME/.env.example $LARA_PATH/$BR_NAME/.env
while getopts b:d: option
do
 case "${option}"
 in
 b) BRANCH=${OPTARG};;
 d) DOMAIN=${OPTARG};;
esac
done

if [ -z "$WS_CONT" ] && [ -z "$DB_CONT" ]; then
   cd $LARA_PATH/$BR_NAME/laradock && docker-compose up --build -d nginx postgres redis beanstalkd
fi

WS_CONT=`docker ps |grep laradock_workspace | awk '{ print $1 }'`
DB_CONT=`docker ps |grep laradock_postgres  | awk '{ print $1 }'`
NGINX_CONT=`docker ps |grep laradock_nginx  | awk '{ print $1 }'`
if [ -z "$WS_CONT" ] || [ -z "$DB_CONT" ]; then
   clear
   echo -e "$WS_CONT"
   echo -e "$RED Some containers are not running. $NC Please check why and start them manually using following commands:" 
   echo -e "" 
   echo -e "cd $LARA_PATH/$BR_NAME/laradock"
   echo -e "docker-compose up --build -d nginx postgres redis beanstalkd"
   echo
   exit 1
fi

chmod -R 777 $LARA_PATH/$BR_NAME/
cd $LARA_PATH/$BR_NAME/laradock && mv env-example .env

clear
echo -e "!!! "
echo -e "!!! $GREEN VARIABLES: $NC" 
echo -e "!!! Branch name (reduced) - " $BR_NAME 
echo -e "!!! Workspace container   - " $WS_CONT
echo -e "!!! Postgres  container   - " $DB_CONT
echo -e "!!! NGINX     container   - " $NGINX_CONT
echo -e "!!! " 

echo -e "$GREEN COPYING SOURCES AND VIRTUAL HOST CREATING $NC"

docker exec $WS_CONT mkdir -p /var/www/$BR_NAME
docker cp $LARA_PATH/$BR_NAME $WS_CONT:/var/www/
docker exec $NGINX_CONT cp /var/www/laradock/project-1.conf.example /etc/nginx/sites-available/$BR_NAME.conf
docker exec $NGINX_CONT sed -i -e "s/project-1.dev/${BR_NAME}.timec.kindgeek.com/g" /etc/nginx/sites-available/$BR_NAME.conf # update server_name
docker exec $NGINX_CONT sed -i -e "s/project-1/${BR_NAME}/g" /etc/nginx/sites-available/$BR_NAME.conf  # nginx config of new branch - update root

docker exec $NGINX_CONT nginx -t
docker exec $NGINX_CONT nginx -s reload 

echo -e "$GREEN UPDATING DB SETTING IN .env FILES $NC" 
docker exec $WS_CONT sed -i "s/\($DB_KEY *= *\).*/\1$DB_VALUE/" $ENV_FILE
docker exec $WS_CONT sed -i "s/\(DB_DATABASE *= *\).*/\1$DB_VALUE/" /var/www/$BR_NAME/.env 

echo -e "$GREEN CREATING NEW INSTANCE OF DB FOR BRANCH $NC"
docker exec $DB_CONT psql postgres -U postgres -c "DROP DATABASE IF EXISTS $BR_NAME"
docker exec $DB_CONT psql postgres -U postgres -c "CREATE DATABASE $BR_NAME"                           
docker exec $DB_CONT psql postgres -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE $BR_NAME to default;"
echo

echo -e "$GREEN RUN COMPOSER $NC"
docker exec $WS_CONT /bin/bash -c "cd /var/www/$BR_NAME && composer install"
docker exec $WS_CONT /bin/bash -c "cd /var/www/$BR_NAME && php artisan vendor:publish --provider="App\Port\Provider\Providers\PortServiceProvider""
docker exec $WS_CONT /bin/bash -c "cd /var/www/$BR_NAME && php artisan key:generate"
docker exec $WS_CONT /bin/bash -c "cd /var/www/$BR_NAME && php artisan hashid:salt:generate"
docker exec $WS_CONT /bin/bash -c "cd /var/www/$BR_NAME && php artisan doctrine:migrations:migrate"
docker exec $WS_CONT /bin/bash -c "cd /var/www/$BR_NAME && php artisan db:seed"
#docker exec $WS_CONT /bin/bash -c "cd /var/www/$BR_NAME && su - laradock -c "cd /var/www/laravel; npm install; /var/www/laravel/node_modules/.bin/apidoc -f .php -i app -o public/documentation"

echo