#!/bin/bash

set -e

cp src/resources/git/hooks/prepare-commit-msg .git/hooks 2> /dev/null | true
cp src/resources/git/hooks/prepare-commit-msg .git/modules/tci/hooks 2> /dev/null | true
cp src/resources/git/hooks/prepare-commit-msg .git/modules/tci-bloody-jenkins/hooks 2> /dev/null | true
cp src/resources/git/hooks/prepare-commit-msg .git/modules/tci-cli/hooks 2> /dev/null | true
cp src/resources/git/hooks/prepare-commit-msg .git/modules/tci-jnlp-node/hooks 2> /dev/null | true
cp src/resources/git/hooks/prepare-commit-msg .git/modules/tci-library/hooks 2> /dev/null | true
cp src/resources/git/hooks/prepare-commit-msg .git/modules/tci-master/hooks 2> /dev/null | true
cp src/resources/git/hooks/prepare-commit-msg .git/modules/tci-pipelines/hooks 2> /dev/null | true

mkdir -p environments/tci-dev-env
cd environments/tci-dev-env

if [ ! -f tci.config ]; then
    cp ../../src/resources/config/tci.config.template tci.config
fi
source tci.config

sed "s/TCI_SERVER_TITLE_TEXT/${TCI_SERVER_TITLE_TEXT}/ ; s/TCI_SERVER_TITLE_COLOR/${TCI_SERVER_TITLE_COLOR}/ ; s/TCI_BANNER_COLOR/${TCI_BANNER_COLOR}/" ../../src/resources/config/tci.css.template > tci.css

if [ ! -f config.yml ]; then
    cp ../../src/resources/config/config.yml.template config.yml
fi
if [ ! -f docker-compose.yml ]; then
    cp ../../src/resources/config/docker-compose.yml.template docker-compose.yml
fi
if [ ! -f org.codefirst.SimpleThemeDecorator.xml ]; then
    cp ../../src/resources/config/org.codefirst.SimpleThemeDecorator.xml.template org.codefirst.SimpleThemeDecorator.xml
fi

# set action defaulted to 'restart'
action='restart'
if [[ $# > 0 ]]; then
   action=$1
fi

if [ ! -n "$TCI_HOST_IP" ]; then
    export TCI_HOST_IP="$(/sbin/ifconfig | grep 'inet ' | grep -Fv 127.0.0.1 | awk '{print $2}' | head -n 1 | sed -e 's/addr://')"
fi
export GIT_PRIVATE_KEY=`cat $GITHUB_PRIVATE_KEY_FILE_PATH`

if [[ "$action" == "info" ]]; then
    if [[ "$TCI_MASTER_BUILD_LOCAL" == "true" ]]; then
        echo [tci-master branch] $TCI_MASTER_BRANCH
    fi
    echo [tci-library branch] $TCI_LIBRARY_BRANCH
    echo [tci-pipelines branch] $TCI_PIPELINES_BRANCH
    echo [Server host IP address] $TCI_HOST_IP
    echo [Private SSH key file path] $GITHUB_PRIVATE_KEY_FILE_PATH
    exit 0
fi

if [[ "$action" == "reset" ]]; then
    read -p "Are you sure you want to reset tci tci-dev [y/N]? " -n 1 -r
    echo    # (optional) move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi
fi

if [[ "$action" == "stop" || "$action" == "restart" || "$action" == "clean-restart" || "$action" == "reset" || "$action" == "stop-reset" ]]; then
   docker-compose down --remove-orphans
   sleep 2
fi

if [[ "$action" == "clean" || "$action" == "clean-restart" || "$action" == "clean-start" ]]; then
    echo 'Nothing to do for now'
    # TODO clean files to enable fresh start
fi

if [[ "$action" == "reset" || "$action" == "stop-reset" ]]; then
   rm -rf .data
   docker rmi tci-master
fi

if [[ "$action" == "start" || "$action" == "clean-start"  || "$action" == "restart" || "$action" == "clean-restart" || "$action" == "reset" ]]; then

    if [[ "$TCI_MASTER_BUILD_LOCAL" == "true" ]]; then
        if [ -d tci-master ]; then
            cd tci-master
            git fetch origin
        else
            git clone git@github.com:TikalCI/tci-master.git
            cd tci-master
        fi
        git fetch origin
        git checkout $TCI_MASTER_BRANCH | true
        git pull origin $TCI_MASTER_BRANCH
        docker build -t tci-master .
        cd ..
    else
        docker pull tikalci/tci-master
        docker tag tikalci/tci-master tci-master
    fi

    mkdir -p .data/jenkins_home/userContent
    cp -f ../../src/resources/images/tci-small-logo.png .data/jenkins_home/userContent | true
    cp -f tci.css .data/jenkins_home/userContent/tci.css | true
    cp -f org.codefirst.SimpleThemeDecorator.xml .data/jenkins_home | true
    docker-compose up -d
    sleep 2
    counter=0
    docker-compose logs -f | while read LOGLINE
    do
        if [[ $counter == 0 ]]; then
            echo -n "*"
        else
            echo -n .
        fi
        [[ "${LOGLINE}" == *"Entering quiet mode. Done..."* ]] && pkill -P $$ docker-compose
        counter=$(( $counter + 1 ))
        if [[ $counter == 5 ]]; then
            counter=0
        fi
    done

fi
