#!/bin/sh

PKG=$1
source functions.sh

## sanity
if [ ! $PKG ]; then
    printc "no PKG specified for the build process, terminating."
    exit 1
fi
if [ $(find ${PKG}*.tar | wc -l) -gt 0 ]; then
    printc "package built, continuing..."
    exit
fi

## build app
./apps/$PKG/$PKG
