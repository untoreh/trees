#!/bin/sh
. ./functions.sh

alprepo="untoreh/pine"
artifact="rootfs.pine_ovz.sq"
dest_path="release_ovz"

## squashfs
cp -p $PWD/utils/*squashfs /usr/bin

## fetch ovz rootfs
fetch_artifact $alprepo $artifact - >$artifact
unsquashfs -d $dest_path $artifact 
repo=${dest_path}/ostree/repo

## we now have the base alp_ovz tree
echo $(realpath $repo)