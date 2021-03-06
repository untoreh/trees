#!/bin/sh

export PKG=$1
. ./functions.sh

## sanity
if [ ! $PKG ]; then
    printc "no PKG specified for the build process, terminating."
    exit 1
fi

## build app
./apps/$PKG/$PKG
