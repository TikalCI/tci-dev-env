#!/bin/bash

set -e

if [[ $# > 0 ]]; then
   submodule=$1
    if [[ $# > 1 ]]; then
       branch=$2
    else
       branch=master
    fi
else
   echo "You must specify the submodule name as a parameter"
   exit 1
fi

git submodule update --init $submodule
cd $submodule
git checkout $branch | true
git status
cd ..
./tci-dev-env.sh info

