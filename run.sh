#!/bin/sh -x

export PKG=$1
source functions.sh

## sanity
if [ ! $PKG ]; then
    printc "no PKG specified for the build process, terminating."
    exit 1
fi
if [ $(find ${PKG}*.tar 2>/dev/null | wc -l) -gt 0 ]; then
    printc "package built, continuing..."
    exit
fi

## build app
./apps/$PKG/$PKG
