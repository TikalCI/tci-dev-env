#!/bin/bash

set -e

function initTciScript {
    BG_RED='\033[0;41;93m'
    BG_GREEN='\033[0;31;42m'
    BG_BLUE='\033[0;44;93m'
    BLUE='\033[0;94m'
    YELLOW='\033[0;93m'
    NC='\033[0m' # No Color

    rm -rf temp 2> /dev/null | true
}

function usage {
    echo -e "\n${BG_BLUE}TCI command usage${NC}\n"
    echo -e "${BLUE}tci.sh <action> [option]${NC}"
    echo -e "\n  where ${BLUE}<action>${NC} is ..."
    echo -e "\t${BLUE}usage${NC} - show this usage description."
    echo -e "\t${BLUE}status${NC} - show tci-dev-env server status."
    echo -e "\t${BLUE}init${NC} - initialize tci-dev-env settings."
    echo -e "\t${BLUE}start${NC} - start the tci-dev-env."
    echo -e "\t${BLUE}stop${NC} - stop the tci-dev-env."
    echo -e "\t${BLUE}restart${NC} - restart the tci-dev-env."
    echo -e "\t${BLUE}apply${NC} - apply changes in the 'setup' folder on the tci-dev-env."
    echo -e "\t${BLUE}reset${NC} - restart the tci-dev-env including ${BG_RED}deleting the server${NC}!."
    echo -e "\t${BLUE}stop-reset${NC} - stop the tci-dev-env and ${BG_RED}delete the server${NC}!."
    echo -e "\t${BLUE}log${NC} - tail the docker-compose log."
}

function setupTciGit {
    cp src/resources/git/hooks/prepare-commit-msg .git/hooks 2> /dev/null | true
    cp src/resources/git/hooks/prepare-commit-msg .git/modules/tci/hooks 2> /dev/null | true
    cp src/resources/git/hooks/prepare-commit-msg .git/modules/tci-bloody-jenkins/hooks 2> /dev/null | true
    cp src/resources/git/hooks/prepare-commit-msg .git/modules/tci-cli/hooks 2> /dev/null | true
    cp src/resources/git/hooks/prepare-commit-msg .git/modules/tci-jnlp-node/hooks 2> /dev/null | true
    cp src/resources/git/hooks/prepare-commit-msg .git/modules/tci-library/hooks 2> /dev/null | true
    cp src/resources/git/hooks/prepare-commit-msg .git/modules/tci-master/hooks 2> /dev/null | true
    cp src/resources/git/hooks/prepare-commit-msg .git/modules/tci-pipelines/hooks 2> /dev/null | true
}

function setupTciScript {
    setupTciGit
    if [ ! -f tci.config ]; then
        cp templates/tci-dev-env/tci.config.template tci.config
        action='init'
    fi
    source templates/tci-dev-env/tci.config.template
    source tci.config

    if [[ "$action" == "init" ]]; then
        . ./scripts/init-tci.sh
    fi

    mkdir -p setup/docker-compose
    if [ ! -f setup/docker-compose/docker-compose.yml.template ]; then
        cp templates/docker-compose/docker-compose.yml.template setup/docker-compose/docker-compose.yml.template
    fi
    echo "# PLEASE NOTICE:" > docker-compose.yml
    echo "# This is a generated file, so any change in it will be lost on the next TCI action!" >> docker-compose.yml
    echo "" >> docker-compose.yml
    cat setup/docker-compose/docker-compose.yml.template >> docker-compose.yml
    numberOfFiles=`ls -1q setup/docker-compose/*.yml 2> /dev/null | wc -l | xargs`
    if [[ "$numberOfFiles" != "0" ]]; then
        cat setup/docker-compose/*.yml >> docker-compose.yml | true
    fi

    mkdir -p setup/tci-master
    cp -n templates/tci-master/*.yml setup/tci-master/ 2> /dev/null | true
    echo "# PLEASE NOTICE:" > tci-master-config.yml
    echo "# This is a generated file, so any change in it will be lost on the next TCI action!" >> tci-master-config.yml
    echo "" >> tci-master-config.yml
    numberOfFiles=`ls -1q setup/tci-master/*.yml 2> /dev/null | wc -l | xargs`
    cat setup/tci-master/*.yml >> tci-master-config.yml | true

    mkdir -p setup/userContent
    cp -n templates/userContent/* setup/userContent/ 2> /dev/null | true
    mkdir -p .data/jenkins_home/userContent
    sed "s/TCI_SERVER_TITLE_TEXT/${TCI_SERVER_TITLE_TEXT}/ ; s/TCI_SERVER_TITLE_COLOR/${TCI_SERVER_TITLE_COLOR}/ ; s/TCI_BANNER_COLOR/${TCI_BANNER_COLOR}/" templates/tci-dev-env/tci.css.template > .data/jenkins_home/userContent/tci.css
    cp setup/userContent/* .data/jenkins_home/userContent 2> /dev/null | true

    if [[ ! -n "$TCI_HOST_IP" || "$TCI_HOST_IP" == "*" ]]; then
        export TCI_HOST_IP="$(/sbin/ifconfig | grep 'inet ' | grep -Fv 127.0.0.1 | awk '{print $2}' | head -n 1 | sed -e 's/addr://')"
    fi
    export GIT_PRIVATE_KEY=`cat $GIT_PRIVATE_KEY_FILE_PATH`

    if [[ "$action" == "init" ]]; then
        exit 0
    fi
}

function info {
    echo -e "\n${BG_BLUE}TCI MASTER SERVER INFORMATION${NC}\n"
    if [[ "$TCI_MASTER_BUILD_LOCAL" == "true" ]]; then
        echo [tci-master branch] $TCI_MASTER_BRANCH
    fi
    echo [tci-library branch] $TCI_LIBRARY_BRANCH
    echo [tci-pipelines branch] $TCI_PIPELINES_BRANCH
    echo [tci-app-set branch] $TCI_APP_SET_BRANCH
    echo -e "[Server host IP address]\t${BLUE}$TCI_HOST_IP${NC}"
    echo -e "[Private SSH key file path]\t${BLUE}$GIT_PRIVATE_KEY_FILE_PATH${NC}"
    echo -e "[TCI HTTP port]\t\t\t${BLUE}$JENKINS_HTTP_PORT_FOR_SLAVES${NC}"
    echo -e "[TCI JNLP port for slaves]\t${BLUE}$JENKINS_SLAVE_AGENT_PORT${NC}"
    echo -e "[Number of master executors]\t${BLUE}$JENKINS_ENV_EXECUTERS${NC}"
}

function stopTciServer {
   docker-compose down --remove-orphans
   sleep 2
}

function startTciServer {
    docker-compose up -d
    sleep 2
}

function showTciServerStatus {
    status=`curl -s -I http://localhost:$JENKINS_HTTP_PORT_FOR_SLAVES | grep "403" | wc -l | xargs`
    if [[ "$status" == "1" ]]; then
        echo -e "\n${BLUE}[TCI status] ${BG_GREEN}tci-dev-env is up and running${NC}\n"
    else
        status=`curl -s -I http://localhost:$JENKINS_HTTP_PORT_FOR_SLAVES | grep "401" | wc -l | xargs`
        if [[ "$status" == "1" ]]; then
            echo -e "\n${BLUE}[TCI status] ${BG_GREEN}tci-dev-env is up and running${NC}\n"
        else
            status=`curl -s -I http://localhost:$JENKINS_HTTP_PORT_FOR_SLAVES | grep "503" | wc -l | xargs`
            if [[ "$status" == "1" ]]; then
                echo -e "\n${BLUE}[TCI status] ${BG_RED}tci-dev-env is starting${NC}\n"
            else
                echo -e "\n${BLUE}[TCI status] ${BG_RED}tci-dev-env is down${NC}\n"
            fi
        fi
    fi
}

function tailTciServerLog {
    SECONDS=0
    docker-compose logs -f -t --tail="1"  | while read LOGLINE
    do
        echo -e "${BLUE}[ET:${SECONDS}s]${NC} ${LOGLINE}"
        if [[ $# > 0 && "${LOGLINE}" == *"$1"* ]]; then
            pkill -P $$ docker-compose
        fi
    done
}

function validateReset {
    read -p "Are you sure you want to reset tci tci-dev [y/N]? " -n 1 -r
    echo    # (optional) move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi
}

function deleteServer {
   rm -rf .data
}

initTciScript

if [[ $# > 0 ]]; then
    action=$1
else
    usage
    exit 1
fi

setupTciScript

if [[ "$action" == "apply" ]]; then
    tailTciServerLog "Running update-config.sh. Done"
    exit 0
fi

if [[ "$action" == "info" ]]; then
    info
    exit 0
fi

if [[ "$action" == "status" ]]; then
    showTciServerStatus
    exit 0
fi

if [[ "$action" == "stop" ]]; then
    stopTciServer
    showTciServerStatus
    exit 0
fi

if [[ "$action" == "restart" ]]; then
    stopTciServer
    startTciServer
    tailTciServerLog "Entering quiet mode. Done..."
    showTciServerStatus
    exit 0
fi

if [[ "$action" == "start" ]]; then
    startTciServer
    tailTciServerLog "Entering quiet mode. Done..."
    showTciServerStatus
    exit 0
fi

if [[ "$action" == "reset" ]]; then
    validateReset
    stopTciServer
    deleteServer
    startTciServer
    tailTciServerLog "Entering quiet mode. Done..."
    showTciServerStatus
    exit 0
fi

if [[ "$action" == "stop-reset" ]]; then
    validateReset
    stopTciServer
    deleteServer
    showTciServerStatus
    exit 0
fi

if [[ "$action" == "log" ]]; then
    tailTciServerLog
    exit 0
fi

usage
