#!/bin/bash
source functions.sh

repo="trub"
tree="tree"
ref="trunk"
repo_mode=${1:-bare-user}

cd /srv
rm -rf ${repo} ${tree}
mkdir -p ${repo} ${tree}
ostree --repo=${repo} --mode=$repo_mode init

ostree --repo=${repo} commit -s $(date)'-build' -b $ref --tree=dir=${tree}