#!/bin/sh
source functions.sh

alprepo="untoreh/pine"
artifact="rootfs.pine_ovz.tgz"
dest_path="release_ovz"

## fetch ovz rootfs
fetch_artifact $alprepo $artifact ${dest_path}
repo=${dest_path}/ostree/repo

## we now have the base alp_ovz tree
echo $(realpath $repo)