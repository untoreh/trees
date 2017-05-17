#!/bin/bash

source functions.sh

remote_repo="untoreh/trub"
artifact="trub.tar"
m_path="target"
dest_path="release"
ref="trunk"

## sanity check
if [ $(find target/* -type d -maxdepth 0 2>/dev/null | wc -l) -eq 0 ]; then
    ## fetch img into release folder, beware the slash
    fetch_artifact $remote_repo /$artifact $dest_path
fi

## trub is a delta, create the repo to apply the delta
source repo.sh bare-user
cmt=$(b64name $dest_path)
## apply the delta
ostree --repo=${repo} static-delta apply-offline $dest_path/$cmt
## tag the delta
ostree --repo=${repo} refs --delete ${ref}
ostree --repo=${repo} refs --create=${ref} $cmt

## we now have the base ubuntu repo
echo $(realpath $repo)
