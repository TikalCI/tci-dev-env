#!/bin/bash

set -e

if [[ $# > 0 ]]; then
   submodule=$1
else
   echo "You must specify the submodule name as a parameter"
   exit 1
fi

git submodule update --init $submodule
cd $submodule
git status
cd ..
./tci-dev-env.sh info

