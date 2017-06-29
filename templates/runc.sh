#!/bin/bash -li
## this script needs the -i(nteractive) flag to spawn ttys for detached containers
shopt -s extglob

ARGS=$@

HELP=
ENTER=
BUNDLE=
DETACH=
runvar=
name=
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
		-soc | --skip-oci-config)
			SKIP_OCI_CONFIG=1
			ARGS=${ARGS//*(-soc|--skip-oci-config)/}
			;;
		-scc | --skip-copi-config)
			SKIP_COPI_CONFIG=1
			ARGS=${ARGS//*(-scc|--skip-copi-config)/}
			;;
		-h | --help)
			HELP=1
			;;      
		enter)
			runvar=true
			ENTER=1
			;;
		run | create)
			runvar=true
			ARGS="$ARGS $nnkr"
			;;
		+([^-]))
			if [ -n "$runvar" -a -z "$name" ]; then
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

## utils
if [ -n "$HELP" ]; then
	/usr/bin/runc.bin $ARGS
	cat <<-EOF
	HELPER:
	- set PRINT_DEBUG for runtime info 
	- use the enter (runc enter [..]) command if exec does not work

	EOF
	exit
fi

## enter subroute
if [ -n "$ENTER" ]; then
	. /proc/cmdline
	nsargs=
	CT="/var/run/runc.d/${name}" 
	CT_PID=$(cat ${CT}/proc.pid) 
	for n in $(ls /proc/${CT_PID}/ns); do
		nsargs="$nsargs -${n:0:1}"
	done
	exec nsenter -F -t $CT_PID $nsargs chroot ${ostree} ${ARGS/?(* $name |* $name)}
fi

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
	printdb "downloading apps list.."
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
		printdb "linking ostree repo for apps.."        
		sup local ostree-apps
	fi
	printdb "installing app image.."
	trees --base $base --name $name
	[ $? != 1 ] || exit 1
	## link containerpilot
	if [ ! -f "$copiref" ]; then
		printdb "tagging container pilot ostree ref.."
		sup local ostree-containerpilot
		touch $copiref
	fi
	printdb "adding copi to image root.."
	ostree checkout --require-hardlinks --union copi $BUNDLE/rootfs
fi

## mount cgroups if not mounted
if ! mountpoint -q /sys/fs/cgroup/cpu,cpuacct,cpuset; then
	printdb "mounting cgroups.."
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
	CT="/var/run/runc.d/${name}"
	mkdir -p $CT
	rm -f $CT/{in,out}
	if [ -z "$(echo $ARGS | grep '\--pid-file')" ]; then
		rm -f $CT/proc.pid
		ARGS="$ARGS --pid-file $CT/proc.pid"
	fi
else
	TTY=true
fi

## generate the runc config
if [ -z "$SKIP_OCI_CONFIG" ]; then
	printdb "generating container config.."
	eval "oci-runtime-tool generate --template $OCI_TEMPLATE_PATH  \
		--hostname ${RUNC_IMAGE_NAME}${NODE} \
		--masked-paths /image.conf \
		--masked-paths /image.env \
		--tty=$TTY \
		$RUNC_IMAGE_CONFIG" >$BUNDLE/config.json
fi

## generate copi config
if [ -z "$SKIP_COPI_CONFIG" ]; then
	printdb "generating copi config.."
	set -a
	. $BUNDLE/rootfs/image.env &>/dev/null
	containerpilot -template -config /etc/containerpilot.json5 -out $BUNDLE/rootfs/containerpilot.json5
fi

## fly away
if [ -n "$DETACH" ]; then
	eval "exec empty -f -i $CT/in -o $CT/out sh -c '/usr/bin/runc.bin $ARGS && procpid=\$(cat $CT/proc.pid); [ -n \"\$procpid\" ] && exec watch -gx kill -0 \$procpid'"
else
	eval "exec /usr/bin/runc.bin $ARGS"
fi