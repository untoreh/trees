#!/bin/bash

. ./functions.sh

remote_repo="untoreh/trub"
artifact="trub.tar"
m_path="target"
dest_path="release"
ref="trunk"

fetch_artifact $remote_repo /$artifact $dest_path

## trub is a delta, create the repo to apply the delta
. ./repo.sh bare-user trub
cmt=$(b64name $dest_path)
## apply the delta
ostree --repo=${repo} static-delta apply-offline $dest_path/$cmt
## tag the delta
ostree --repo=${repo} refs --delete ${ref}
ostree --repo=${repo} refs --create=${ref} $cmt

## we now have the base ubuntu repo
echo $(realpath $repo)
