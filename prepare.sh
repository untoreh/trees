#!/bin/sh

source functions.sh

cat << EOF >>/etc/apk/repositories
http://dl-cdn.alpinelinux.org/alpine/edge/testing
EOF
sync
apk add --update-cache  \
 bash  \
 wget  \
 git  \
 unzip  \
 tar  \
 xz  \
 coreutils  \
 binutils  \
 util-linux \
 libressl  \
 ca-certificates  \
 ostree

install_glib
