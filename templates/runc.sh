#!/bin/bash -l

ARGS=$@

BUNDLE=$PWD
while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
                -b | --bundle)
                        BUNDLE=$2
                        ;;
                -*=* | --*=*)
                        k=${key/=*}
                        v=${key#*=}
                        case $k in
                                -b | --bundle)
                                BUNDLE=$v
                                ;;
                        esac
                        ;;
        esac
        shift
done

## source extra image config
. $BUNDLE/rootfs/image.conf

OCI_TEMPLATE_PATH={$OCI_TEMPLATE_PATH:-/etc/runc.json}

oci-runtime-tool generate --template $OCI_TEMPLATE_PATH  \
    --hostname ${RUNC_IMAGE_NAME}${NODE} \
    --masked-paths /image.conf \
    --masked-paths /image.env \
    $RUNC_IMAGE_CONFIG > $BUNDLE/config.json


exec /usr/bin/runc.bin $ARGS