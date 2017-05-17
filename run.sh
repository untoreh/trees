#!/bin/sh

PKG=$1
source functions.sh &>/dev/null

## sanity
if [ ! $PKG ]; then
    printc "no PKG specified for the build process, terminating."
    exit 1
fi

## prepare
printc "preparing..."
./prepare.sh

## build app
bash apps/$PKG
