#!/bin/bash -li
## this script needs the -i(nteractive) flag to spawn ttys for detached containers
shopt -s extglob

ARGS=$@

BUNDLE=
DETACH=
runvar=
nnkr="--no-new-keyring"
while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
                -b | --bundle)
                        BUNDLE=$2
                        ;;
                -d | --detach)
                        DETACH=true
                        ;;
                --no-new-keyring)
                        nnkr=
                        ;;
                run | create)
                        runvar=true
                        ARGS="$ARGS $nnkr"
                        ;;
                +([^-]))
                        if [ -n "$runvar" ]; then
                                name=$key
                        fi
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

if [ -z "$BUNDLE" ]; then
        ## check if current dir is a bundle
        if [ -s config.json -a -d rootfs -a -n "$runvar" ]; then
                BUNDLE=$PWD
        else 
                if [ -n "$name" ]; then
                        BUNDLE="/sysroot/ostree/repo/$name"
                        ARGS="$ARGS --bundle $BUNDLE"
                else
                        ## nothing to do pass the command along
                        exec /usr/bin/runc.bin $ARGS                      
                fi
        fi
fi

OCI_TEMPLATE_PATH=${OCI_TEMPLATE_PATH:-"/etc/runc.json"}
curV=$(cat /etc/pine)
apps_url="https://cdn.rawgit.com/untoreh/trees/master/appslist?v=${curV}"
listdir="$HOME/.cache/appslist"
listfail="$HOME/.cache/appslist_fail"
appslist="$(cat $listdir 2>/dev/null)"
copiref="$HOME/.cache/copiref"
name=$(basename $BUNDLE)
bundle_found=$([ -d $BUNDLE ] && echo "yes")
appsrepo="/var/lib/apps/repo"

if [ -z "$appslist" ]; then
        mkdir -p $HOME/.cache
        fetch_artifact $apps_url - >$listdir
fi

## check app name
appline=$(cat $listdir | grep $name)
if [ -z "$appline" -a -z "$bundle_found" ]; then
        err "App name not found in appslist or bundle path has not been found"
        fails=$(cat $listfail 2>/dev/null || echo 0)
        if [ "$fails" -gt 5 ]; then
                rm $listdir $copiref
                echo "0" >$listfail
        else
                echo $((fails+1)) >$listfail
        fi
        exit 1
fi

## get the base of the app
base=$(echo $appline | sed -r 's/.*:|,.*//g')

## install the app if bundle path is empty
if [ -z "$bundle_found" ]; then
        ## link ostree repo
        if [ ! -d $appsrepo ]; then
                sup local ostree-apps
        fi
        trees --base $base --name $name
        [ $? != 1 ] || exit 1
        ## link containerpilot
        if [ ! -f "$copiref" ]; then
                sup local ostree-containerpilot
                touch $copiref
        fi
        ostree checkout --require-hardlinks --union copi $BUNDLE/rootfs
fi

## mount cgroups if not mounted
if ! mountpoint -q /sys/fs/cgroup/cpu,cpuacct,cpuset; then
        mkdir /sys/fs/cgroup/freezer,devices
        mount -t cgroup cgroup /sys/fs/cgroup/freezer,devices -o freezer,devices
        mkdir /sys/fs/cgroup/cpu,cpuacct,cpuset
        mount -t cgroup cgroup /sys/fs/cgroup/cpu,cpuacct,cpuset/ -o cpu,cpuacct,cpuset
fi

## source extra image config
. $BUNDLE/rootfs/image.conf &>/dev/null

## tty DO NOT edit ARGS after this anymore
if [ -n "$DETACH" ]; then
        TTY=false
        [ -p $BUNDLE/in ] || mkfifo $BUNDLE/in
        ARGS="$ARGS 1>$BUNDLE/out 2>$BUNDLE/err 0<$BUNDLE/in"
else
        TTY=true
fi

## generate the runc config
eval "oci-runtime-tool generate --template $OCI_TEMPLATE_PATH  \
    --hostname ${RUNC_IMAGE_NAME}${NODE} \
    --masked-paths /image.conf \
    --masked-paths /image.env \
    --tty=$TTY \
    $RUNC_IMAGE_CONFIG" >$BUNDLE/config.json

## generate copi config
set -a
source $BUNDLE/rootfs/image.env &>/dev/null
containerpilot -template -config /etc/containerpilot.json5 -out $BUNDLE/rootfs/containerpilot.json5

## fly away
eval "exec /usr/bin/runc.bin $ARGS"