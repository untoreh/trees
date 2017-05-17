#!/bin/bash

source functions.sh

alprepo="untoreh/pine"
artifact="image.pine.tgz"
img="image.pine"
m_path="target"
dest_path="release"

## sanity check
if [ $(find target/* -type d -maxdepth 0 | wc -l) -eq 0 ]; then
    ## fetch img into release folder
    fetch_artifact $alprepo $artifact $dest_path

    mount_image ${dest_path}/${img} $m_path
fi

## ostree repo is in mountpath p3
repo=${m_path}/p3/ostree/repo

## we now have the base alp tree
echo $(realpath $repo)
