#!/bin/sh

. ./functions.sh

cat << EOF >>/etc/apk/repositories
http://dl-cdn.alpinelinux.org/alpine/edge/testing
EOF
sync
apk add --update-cache  \
 bash  \
 wget  \
 curl \
 git  \
 unzip  \
 tar  \
 xz  \
 coreutils  \
 binutils  \
 findutils \
 util-linux \
 libressl  \
 ca-certificates  \
 ostree

install_glib
