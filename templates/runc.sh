#!/bin/bash -li
## this script needs the -i(nteractive) flag to spawn ttys for detached containers
shopt -s extglob

ARGS=$@

HELP=
ENTER=
RESTART=
ATTACH=
CD=
DELETE=
BUNDLE=
DETACH=
runvar=
name=
nnkr="--no-new-keyring"
nopivot="--no-pivot"
while [[ $# -gt 0 ]]; do
	key="$1"
	case $key in
		-b | --bundle)
			BUNDLE=$2
			;;
		-d | --detach)
			DETACH=1
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
		bun | bundle)
			runvar=true
			CD=1
			;;
		ent | enter)
			runvar=true
			ENTER=1
			;;
		att | attach)
			runvar=true
			ATTACH=1
			;;
		run)
			runvar=true
			ARGS="$ARGS $nnkr $nopivot"
			;;
		create)
			runvar=true
			ARGS="$ARGS $nnkr"
			DETACH=1
			;;
		res | restart)
			runvar=true
			ARGS="${ARGS/#restart/run} $nnkr"
			RESTART=1
			DETACH=1
			;;
		delete)
			runvar=true
			DELETE=1
			;;
		+([^-]))
			if [ -n "$runvar" -a -z "$name" ]; then
				name=$key
			fi
			;;
		-*=* | --*=*)
			k=${key/=*/}
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

## common vars
appsrepo="/var/lib/apps/repo"

## help subroute
if [ -n "$HELP" ]; then
	/usr/bin/runc.bin $ARGS
	cat <<-EOF
	HELPER:
	PRINT_DEBUG for runtime info
	ent, enter  			(runc enter [..]) command if exec does not work
	bun, bundle			 	setup shell command to quickly cd into app rootfs
	att, attach 			see container logs			

	EOF
	exit
fi

## enter subroute
if [ -n "$ENTER" -a -n "$name" ]; then
	. /proc/cmdline
	nsargs=
	CT="/var/run/runc.d/${name}"
  [ -e ${CT}/proc.pid ] &&
      CT_PID=$(<${CT}/proc.pid) ||
          CT_PID=$(sed -r 's/.*init_process_pid":([^,]*).*/\1/' < /run/runc/${name}/state.json)
	for n in $(ls /proc/${CT_PID}/ns); do
		nsargs="$nsargs -${n:0:1}"
	done
	exec nsenter -F -t $CT_PID $nsargs chroot ${ostree} ${ARGS/?(* $name |* $name)/}
fi

## attach subroute
if [ -n "$ATTACH" -a -n "$name" ]; then
	if [ ! -e /var/run/runc.d/${name}/out ]; then
		echo "no output found.."
		exit 1
	else
		exec cat /var/run/runc.d/${name}/out
	fi
fi

## delete subroute
if [ -n "$DELETE" -a -n "$name" ]; then
	/usr/bin/runc.bin $ARGS
	## delete checked out tree
	if [ $? = 0 ]; then
		rm -rf ${appsrepo}/${name}
		exit
	else
		exit 1
	fi
fi

## cd subroute
if [ -n "$CD" ]; then
	exec echo "bunc(){
		 	cd $appsrepo/\$1 2>/dev/null || echo 'app rootfs not found..';
		 }" | tee -a /etc/profile.d/runc.sh
fi

## restart subroute
if [ -n "$RESTART" -a -n "$name" ]; then
	BUNDLE=$(/usr/bin/runc.bin list | grep -E "^$name" | awk '{print $4}')
	if [ -n "$BUNDLE" ]; then 
		ARGS="${ARGS/@( ${name} )/ ${name} -d --bundle ${BUNDLE} }"
		/usr/bin/runc.bin kill ${name}
		timeout 10 bash -c "while [ \"\$(/usr/bin/runc.bin list | \
			grep -E ^$name | awk '{print \$3}')\" != stopped ]; do
			sleep 0.5
		done"
		/usr/bin/runc.bin delete ${name}
	else
		err "container $name does not exist"
		exit 1
	fi
fi

## run/create subroute
if [ -z "$BUNDLE" ]; then
	## check if current dir is a bundle ( no name provided )
	if [ -s config.json -a -d rootfs -a -n "$runvar" -a -z "$name" ]; then
		BUNDLE=$PWD
	else
		if [ -n "$name" ]; then
			BUNDLE="${appsrepo}/${name}"
			ARGS="$ARGS --bundle $BUNDLE"
		else
			## nothing to do pass the command along
			exec /usr/bin/runc.bin $ARGS
		fi
	fi
fi

OCI_TEMPLATE_PATH=${OCI_TEMPLATE_PATH:-"/etc/runc.json"}
curV=${PINE:-pine-$(cat /etc/pine)}
apps_url="https://gitcdn.xyz/repo/untoreh/trees/${curV}/appslist"
listdir="$HOME/.cache/appslist"
listfail="$HOME/.cache/appslist_fail"
appslist="$(cat $listdir 2>/dev/null)"
copiref="$HOME/.cache/copiref"
name=$(basename $BUNDLE)
bundle_found=$([ -d $BUNDLE ] && echo "yes")

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
		echo $((fails + 1)) >$listfail
	fi
	exit 1
fi

## get the base of the app
base=$(echo $appline | sed -r 's/.*:|,.*//g')

## install the app if bundle path is empty
if [ -z "$bundle_found" ]; then
	## checkout app rootfs
	printdb "checking out app.."
	trees checkout --base $base --name $name
	## link containerpilot
	if [ ! -f "$copiref" ]; then
		printdb "tagging container pilot ostree ref.."
		sup local ostree-containerpilot
		touch $copiref
	fi
	## checkout containerpilot in app rootfs
	printdb "adding copi to image root.."
	trees checkout --name copi $BUNDLE/rootfs
fi

## mount cgroups if not mounted
if ! mountpoint -q /sys/fs/cgroup/cpu,cpuacct,cpuset && grep ^2 < <(uname -r); then
	printdb "mounting cgroups.."
	mkdir /sys/fs/cgroup/freezer,devices
	mount -t cgroup cgroup /sys/fs/cgroup/freezer,devices -o freezer,devices
	mkdir /sys/fs/cgroup/cpu,cpuacct,cpuset
	mount -t cgroup cgroup /sys/fs/cgroup/cpu,cpuacct,cpuset/ -o cpu,cpuacct,cpuset
fi

## copy local image files if avail
if [ -d /srv/${name} ]; then
	cp /srv/${name}/{image.conf,image.env} -t $BUNDLE/rootfs &>/dev/null
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
## fix for unavailable caps
if [ -z "$SKIP_OCI_CONFIG" ]; then
	printdb "generating container config.."
	eval "oci-runtime-tool generate --template $OCI_TEMPLATE_PATH  \
		--hostname ${RUNC_IMAGE_NAME}${NODE} \
		--linux-masked-paths /image.conf \
		--linux-masked-paths /image.env \
		--linux-masked-paths /prestart.sh \
		--linux-masked-paths /poststart.sh \
		--linux-masked-paths /poststop.sh \
		--process-terminal=$TTY \
		$RUNC_IMAGE_CONFIG" |  \
		grep -Ev "CAP_SYSLOG|CAP_WAKE_ALARM|CAP_BLOCK_SUSPEND|CAP_AUDIT_READ" | \
		sed -r 's/(CAP_MAC_ADMIN"),/\1/' \
		>$BUNDLE/config.json
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
	eval "exec empty -f -i $CT/in -o $CT/out sh -c '/usr/bin/runc.bin $ARGS && procpid=\$(cat $CT/proc.pid); [ -n \"\$procpid\" ] && exec tail -f --pid=\$procpid /dev/null'"
else
	eval "exec /usr/bin/runc.bin $ARGS"
fi
