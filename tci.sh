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

action='restart'
if [[ $# > 0 ]]; then
    action=$1
fi
if [[ "$action" == "upgrade" ]]; then
    git pull origin HEAD
fi

if [ ! -f tci.config ]; then
    cp src/resources/templates/tci.config.template tci.config
    action='init'
fi
source src/resources/templates/tci.config.template
source tci.config

if [[ "$action" == "init" || "$action" == "upgrade" ]]; then
    echo "Initializing tci-server. You'll need to restart the server after that action."
    . ./src/scripts/init-tci.sh
fi

if [ ! -f docker-compose.yml ]; then
    cp src/resources/templates/docker-compose.yml.template docker-compose.yml
fi

if [ ! -f config.yml ]; then
    cp src/resources/templates/config.yml.template config.yml
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
    echo [TCI HTTP port] $JENKINS_HTTP_PORT_FOR_SLAVES
    echo [TCI JNLP port for slaves] $JENKINS_SLAVE_AGENT_PORT
    echo [TCI number of master executors] $JENKINS_ENV_EXECUTERS
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
   rm -f docker-compose.yml
   docker rmi $TCI_MASTER_VERSION | true
fi

if [ ! -f docker-compose.yml ]; then
    cp src/resources/templates/docker-compose.yml.template docker-compose.yml
fi

if [[ "$action" == "start" || "$action" == "clean-start"  || "$action" == "restart" || "$action" == "clean-restart" || "$action" == "reset" ]]; then
    mkdir -p .data/jenkins_home/userContent
    cp -f src/resources/images/tci-small-logo.png .data/jenkins_home/userContent | true
    sed "s/TCI_SERVER_TITLE_TEXT/${TCI_SERVER_TITLE_TEXT}/ ; s/TCI_SERVER_TITLE_COLOR/${TCI_SERVER_TITLE_COLOR}/ ; s/TCI_BANNER_COLOR/${TCI_BANNER_COLOR}/" src/resources/templates/tci.css.template > .data/jenkins_home/userContent/tci.css
    cp -f src/resources/templates/org.codefirst.SimpleThemeDecorator.xml.template .data/jenkins_home/org.codefirst.SimpleThemeDecorator.xml
    docker-compose up -d
    sleep 2
    SECONDS=0
    docker-compose logs -f | while read LOGLINE
    do
        echo "[ET ${SECONDS}s] ${LOGLINE}"
        [[ "${LOGLINE}" == *"Entering quiet mode. Done..."* ]] && pkill -P $$ docker-compose
    done
    action="status"
fi

if [[ "$action" == "status" ]]; then
    status=`curl -s -I http://localhost:$JENKINS_HTTP_PORT_FOR_SLAVES | grep "403" | wc -l | xargs`
    if [[ "$status" == "1" ]]; then
        echo "[TCI status] tci-server is up and running"
    else
        status=`curl -s -I http://localhost:$JENKINS_HTTP_PORT_FOR_SLAVES | grep "401" | wc -l | xargs`
        if [[ "$status" == "1" ]]; then
            echo "[TCI status] tci-server is up and running"
        else
            status=`curl -s -I http://localhost:$JENKINS_HTTP_PORT_FOR_SLAVES | grep "503" | wc -l | xargs`
            if [[ "$status" == "1" ]]; then
                echo "[TCI status] tci-server is starting"
            else
                echo "[TCI status] tci-server is down"
            fi
        fi
    fi
fi
