#!/bin/bash

shopt -s expand_aliases &>/dev/null
[ ${GIT_TOKEN:-} ] && gh_token="?access_token=${GIT_TOKEN}"
cn="\033[1;32;40m"
cf="\033[0m"
printc() {
    echo -e "${cn}${@}${cf}"
}
printdb() {
    [ -n "$PRINT_DEBUG" ] && echo -e "${cn}${@}${cf}"
}
err() {
    echo $@ 1>&2
}
rse()
{
    ((eval $(for phrase in "$@"; do echo -n "'$phrase' "; done)) 3>&1 1>&2 2>&3 | sed -e "s/^\(.*\)$/$(echo -en \\033)[31;1m\1$(echo -en \\033)[0m/") 3>&1 1>&2 2>&3
}

git_versions() {
    git ls-remote -t git://github.com/"$1".git | awk '{print $2}' | cut -d '/' -f 3 | grep -v "\-rc" | cut -d '^' -f 1 | sed 's/^v//'
}

pine_version() {
    git_versions untoreh/pine | sort -bt- -k1nr -k2nr | head -1
}

last_version() {
    git_versions $1 | sort -bt. -k1nr -k2nr -k3r -k4r -k5r | head -1
}

last_version_g(){
    git_versions $1 | grep "[0-9]" | sort -Vr | head -1
}

## $1 repo $2 type
last_release() {
    if [ -n "$2" ]; then
        latest=
        release_type="$2"
    else
        latest="/latest"
    fi
    wget -qO- https://api.github.com/repos/${1}/releases$latest \
        | awk '/tag_name/ { print $2 }' | grep "$release_type" | head -1 | sed -r 's/",?//g'
}

## $1 repo $2 tag name
tag_id() {
    [ -n "$2" ] && tag_name="tags/${2}" || tag_name=latest
    wget -qO- https://api.github.com/repos/${1}/releases/${tag_name} | grep '"id"' | head -1 | grep -o "[0-9]*"
}
## $1 repo $2 old tag $3 new tag
switch_release_tag(){
    tid=$(tag_id ${1} ${2})
    new_tid=$(tag_id ${1} ${3})
    curl -X DELETE -u $GIT_USER:$GIT_TOKEN https://api.github.com/repos/${1}/releases/${new_tid}
    ## also specify master otherwise tag sha is not updated despite it being master anyway
    curl -X PATCH -u $GIT_USER:$GIT_TOKEN \
    -d '{"tag_name": "'${3}'", "name": "'${3}'", "target_commitish": "master"}' \
    https://api.github.com/repos/${1}/releases/${tid}
}

## $1 repo $2 currentTag(YY.MM-X)
next_release() {
    if [ -n "$2" ]; then
        cur_tag="$2"
    else
        return
    fi
    cur_D=$(echo $cur_tag | cut -d- -f1)
    ## get this month tags
    near_tags=$(git ls-remote -t https://github.com/${1} --match "$cur_D*" | awk '{print $2}' \
        | cut -d '/' -f 3 | cut -d '^' -f 1 | sed 's/^v//' | sort -bt- -k2n)
    ## loop until we find a valid release
    while
        cur_tag=$(echo "$near_tags" | awk '/'$cur_tag'/{getline; print $0}')
        echo "looking for releases tagged $cur_tag" 1>&2
        next_release=$(wget -qO- https://api.github.com/repos/${1}/releases/tags/${cur_tag}${gh_token})
        [ -z "$next_release" -a -n "$cur_tag" ]
    do :
    done
    echo $cur_tag
}

## get a valid next tag for the current git repo format: YY.MM-X
md() {
    giturl=$(git remote show origin | grep -i fetch | awk '{print $3}')
    [ -z "$(echo $giturl | grep github)" ] && echo "'md' tagging method currently works only with github repos, terminating." && exit 1
    prevV=$(git ls-remote -t $giturl | awk '{print $2}' | cut -d '/' -f 3 | grep -v "\-rc" | cut -d '^' -f 1 | sed 's/^v//')
    if [ -n "$tag_prefix" ]; then
        prevV=$(echo "$prevV" | grep $tag_prefix | sed 's/'$tag_prefix'-//' | sort -bt- -k1nr -k2nr | head -1)
    else
        echo "no \$tag_prefix specified, using to prefix." 1>&2
        prevV=$(echo "$prevV" | sort -bt- -k1nr -k2nr | head -1)
    fi
    ## prev date
    prevD=$(echo $prevV | cut -d- -f1)
    ## prev build number
    prevN=$(echo $prevV | cut -d- -f2)
    ## gen new release number
    newD=$(date +%y.%m)
    if [[ $prevD == $newD ]]; then
        newN=$((prevN + 1))
    else
        newN=0
    fi
    newV=$newD-$newN
    echo "$newV"
}

## $1 repo
## $2 tag
last_release_date() {
    if [ -n "$2" ]; then
        tag="tags/$2"
    else
        tag="latest"
    fi
    local date=$(wget -qO- https://api.github.com/repos/${1}/releases/${tag} | grep created_at | head -n 1 | cut -d '"' -f 4)
    [ -z "$date" ] && echo 0 && return
    date -d "$date" +%Y%m%d%H%M%S
}

## $1 release date
## $2 time span eg "7 days ago"
release_older_than() {
    if [ $(echo -n $1 | wc -c) != 14 -a "$1" != 0 ]; then
        err  "wrong date to compare"
    fi
    release_d=$1
    span_d=$(date --date="$2" +%Y%m%d%H%M%S)
    if [ $span_d -ge $release_d ]; then
        return 0
    else
        return 1
    fi
}

## get mostly local vars
diff_env(){
    bash -cl 'set -o posix && set >/tmp/clean.env'
    set -o posix && set >/tmp/local.env && set +o posix
    diff /tmp/clean.env \
        /tmp/local.env | \
        grep -E "^>|^\+" | \
        grep -Ev "^(>|\+|\+\+) ?(BASH|COLUMNS|LINES|HIST|PPID|SHLVL|PS(1|2)|SHELL|FUNC)" | \
        sed -r 's/^> ?|^\+ ?//'
}

## $1 repo:tag
## $2 artifact name
## $3 dest dir
## $4 extra wget options
fetch_artifact() {
    if [ "${1:0:4}" = "http" ]; then
        art_url="$1"
        artf=$(basename $art_url)
        dest="$2"
        shift 2
    else
        local repo_fetch=${1/:*/} repo_tag=${1/*:/} draft= opts=
        [ -z "$repo_tag" -o "$repo_tag" = "$1" ] && repo_tag=/latest || repo_tag=/tags/$repo_tag
        [ "$repo_tag" = "/tags/draft" ] && repo_tag=$gh_token && draft=true
        artf="$2"
        if [ -n "$draft" ]; then
            art_url=$(wget -qO- https://api.github.com/repos/${repo_fetch}/releases${repo_tag} \
                | grep "${artf}" -B 3 | grep '"url"' | head -n 1 | cut -d '"' -f 4)${gh_token}
            trap "unset -f wget" SIGINT SIGTERM SIGKILL SIGHUP RETURN EXIT
            wget(){ /usr/bin/wget --header "Accept: application/octet-stream" $@; }
        else
            art_url=$(wget -qO- https://api.github.com/repos/${repo_fetch}/releases${repo_tag} \
                | grep browser_download_url | grep ${artf} | head -n 1 | cut -d '"' -f 4)
        fi
        dest="$3"
        shift 3
    fi
    [ -z "$(echo "$art_url" | grep "://")" ] && err "no url found" && return 1
    ## if no destination dir stream to stdo
    case "$dest" in
        "-")
        wget $@ $art_url -qO-
        ;;
        "-q")
        return 0
        ;;
        *)
        mkdir -p $dest
        if [ $(echo "$artf" | grep -E "(gz|tgz|xz|7z)$") ]; then
            wget $@ $opts $art_url -qO- | tar xzf - -C $dest
        else
            if [ $(echo "$artf" | grep -E "zip$") ]; then
                wget $@ $hader $art_url -qO artifact.zip && unzip artifact.zip -d $dest
                rm artifact.zip
            else
                if [ $(echo "$artf" | grep -E "bz2$") ]; then
                    wget $@ $opts $art_url -qO- | tar xjf - -C $dest
                else
                    wget $@ $opts $art_url -qO- | tar xf - -C $dest
                fi
            fi
        fi
    esac
}

## $@ files/folders
export_stage(){
    [ -z "$pkg" -o -z "$STAGE" ] && err "pkg or STAGE undefined, terminating" && exit 1
    which hub &>/dev/null || get_hub
    diff_env >stage.env
    tar czf ${pkg}_stage_${STAGE}.tgz stage.env $@

    hub release edit -d -a ${pkg}_stage_${STAGE}.tgz -m "${pkg}_stage" ${pkg}_stage || \
    hub release create -d -a ${pkg}_stage_${STAGE}.tgz -m "${pkg}_stage" ${pkg}_stage
}

## $1 repo
import_stage(){
    [ -z "$pkg" -o -z "$STAGE" -o -z "$1" ] && err "pkg, STAGE, or repo undefined, terminating" && exit 1
    PREV_STAGE=$((STAGE - 1))
    fetch_artifact ${1}:draft ${pkg}_stage_${PREV_STAGE}.tgz $PWD
    . ./stage.env || cat stage.env | tail +2 > stage1.env && . ./stage1.env
}

## $1 repo
check_skip_stage(){
    [ -n "$PKG" ] && pkg=$PKG
    [ -z "$pkg" -o -z "$STAGE" -o -z "$1" ] && err "pkg, STAGE, or repo undefined, terminating" && exit 1
    fetch_artifact ${1}:draft ${pkg}_stage_$STAGE.tgz -q && return 0 || return 1
}

## $1 repo
cleanup_stage(){
    [ -z "$pkg" ] && pkg=$PKG
    [ -z "$pkg" ] && err "pkg undefined, terminating" && exit 1
    which github-release &>/dev/null || get_ghr
    local u=${1/\/*} r=${1/*\/}
    err "cleaning up drafts..."
    github-release delete -u $u -r $r -t ${pkg}_stage
}
## $1 image file path
## $2 mount target
## mount image, ${lon} populated with loop device number
mount_image() {
    umount -Rfd $2 2>/dev/null
    rm -rf $2 && mkdir $2
    lon=0
    while [ -z "$(losetup -P /dev/loop${lon} $(realpath ${1}) 2>/dev/null && echo true)" ]; do
        lon=$((lon + 1))
        [ $lon -gt 10 ] && (err "failed mounting image $1" && return 1)
        sleep 1
    done
    ldev=/dev/loop${lon}
    tgt=$(realpath $2)
    mkdir -p $tgt
    for p in $(find /dev/loop${lon}p*); do
        mp=$(echo "$p" | sed 's~'$ldev'~~')
        mkdir -p $tgt/$mp
        mount -o nouuid $p $tgt/$mp 2>/dev/null
    done
}

## $1 overdir
## $2 lowerdir
mount_over(){
    local pkg=$1 lodir=$2
    [ -z "$pkg" ] && return 1
    [ -z "$lodir" ] && lodir="${pkg}-lo"
    mkdir -p ${pkg} $lodir ${pkg}-wo ${pkg}-up
    mount -t overlay -o lowerdir=$lodir,workdir=${pkg}-wo,upperdir=${pkg}-up none ${pkg} ||
        { err "overlay failed for $pkg" && exit 1; }
}

## $1 rootfs
mount_hw() {
    rootfs=$1
    mkdir -p $rootfs
    cd $rootfs
    mkdir -p dev proc sys
    mount --bind /dev dev
    mount --bind /proc proc
    mount --bind /sys sys
    cd -
}

## $1 rootfs
umount_hw() {
    rootfs=$1
    cd $rootfs || return 1
    umount dev
    umount proc
    umount sys
    cd -
}

## $@ apk args
## install alpine packages
apkc() {
    initdb=""
    root_path=$(realpath $1)
    apkrepos=${root_path}/etc/apk
    shift
    mkdir -p ${apkrepos}
    if [ ! -f "${apkrepos}/repositories" ]; then
        cp /etc/apk/repositories ${apkrepos}
        initdb="--initdb"
    fi
    apk --arch x86_64 --allow-untrusted --root ${root_path} $initdb --no-cache $@
}

## go env setup
go_env(){
    mkdir -p /go
    export GOPATH=/go GOROOT=/usr/lib/go
}

## $1 ref
## routine pre-modification actions for ostree checkouts
prepare_rootfs() {
    rm -rf ${1}
    mkdir ${1}
    cd $1
    mkdir -p var var/cache/apk usr/lib usr/bin usr/sbin usr/etc
    mkdir -p etc lib lib64 bin sbin
    cd -
}

## $1 $pkg
copy_image_cfg() {
    local pkg=$1
    if [ ! -d "${pkg}" ]; then
        err "package root not found, terminating."
        exit 1
    fi
    cp $PWD/templates/${pkg}/{image.conf,image.env} ${pkg}/
}

## $1 ref
## $2 skip links/ct root
## routing after-modification actions for ostree checkouts
wrap_rootfs() {
    [ -z "$1" ] && (
        err "no target directory provided to wrap_rootfs"
        exit 1
    )
    cd ${1}
    case "$2" in
        "-s")
        ;;
        "-c")
        ## delete links
        rm -f root sysroot srv tmp opt mnt home ostree 2>/dev/null
        mkdir -p  root sysroot srv tmp opt mnt home \
            var/log var/cache var/spool var/tmp
        ;;
        *)
        for l in usr/etc,etc usr/lib,lib usr/lib,lib64 usr/bin,bin usr/sbin,sbin; do
            IFS=','
            set -- $l
            cp -a --remove-destination ${2}/* ${1} &>/dev/null
            rm -rf $2
            ln -sr $1 $2
            unset IFS
        done
        ;;
    esac
    rm -rf var/cache/apk/*
    umount -Rf dev proc sys run &>/dev/null
    rm -rf dev proc sys run
    mkdir dev proc sys run
    cd -
}

## mounts the base tree for the pkg
base_tree(){
    if [ -z "$pkg" ]; then
        err "variables not defined."
        exit 1
    fi
    rm -rf ${pkg}
    if [ "$1" != none ]; then
        repo_path=$(./fetch-${1:-alp}-tree.sh | tail -1)
        repo_local="${PWD}/lrepo"
        ostree checkout --repo=${repo_path} --union ${ref} ${pkg}-lo
        ln -sr ${pkg}/usr/etc ${pkg}/etc || mkdir -p ${pkg}/etc
        mount_over $pkg
    fi
    mount_hw $pkg
    cd $pkg
    mkdir -p var/cache/apk usr/local/{bin,sbin} usr/{bin,sbin}
    cd -
    alias crc="chroot $pkg"
}

## create tar archives for bare and ovz from the raw files tree
package_tree(){
    if [ -z "$pkg" -o \
        -z "$rem_repo" ]; then
        err "variables not defined."
        exit 1
    fi
    ## -- bare/kvm --
    ## if no base tree was used fetch the tree to commit to the repo
    if [ -z "$repo_path" ]; then
        repo_path=$(./fetch-alp-tree.sh | tail -1)
        repo_local="${PWD}/lrepo"
    fi
    mount_over $repo_local $repo_path
    ## commit tree to app branch
    rev=$(ostree --repo=${repo_local} commit -s "$(date)-${pkg}-build" \
        --skip-if-unchanged --link-checkout-speedup -b ${pkg} ${pkg})

    ## get the last app checksum from remote
    old_csum=$(fetch_artifact ${rem_repo}:${pkg} ${pkg}.sum -)
    ## get checksum of committed branch
    new_csum=$(ostree --repo=${repo_local} ls ${pkg} -Cd | awk '{print $5}')
    ## end if unchanged
    compare_csums

    ## create delta of app branch
    ostree --repo=${repo_local} static-delta generate --from=${ref} ${pkg} \
        --inline --min-fallback-size 0 --filename=${rev}

    ## checksum and compress
    echo $new_csum >${pkg}.sum
    tar cvf ${pkg}.tar ${rev}

    ## -- ovz --
    repo_local=$(./fetch-alp_ovz-tree.sh | tail -1)
    ## commit tree to app branch
    rev=$(ostree --repo=${repo_local} commit -s "$(date)-${pkg}-build" \
        --skip-if-unchanged --link-checkout-speedup -b ${pkg} ${pkg})
    ## skip csum comparison, if bare image is different so is ovz
    ## create delta of app branch
    ostree --repo=${repo_local} static-delta generate --from=${ref} ${pkg} \
        --inline --min-fallback-size 0 --filename=${rev}

    ## compress
    tar cvf ${pkg}_ovz.tar ${rev}
}

## $@ packages to install
install_tools() {
    setup=false
    tools="$@"
    for t in $tools; do
        if [ -z "$(apk info -e $t)" ]; then
            setup=true
            toinst="$toinst $t"
        fi
    done
    $setup && apk add --no-cache $toinst
}

## $1 path to search
## return the name of the first file named with 64numchars
b64name() {
    echo $(basename $(find $1 | grep -E [a-z0-9]{64}))
}

compare_csums() {
    if [ "$new_csum" = "$old_csum" ]; then
        printc "${pkg} already up to update."
        echo $pkg >>file.up
        exit
    fi
    printc "csums different."
}

## fetch github hub bin
get_hub() {
    mkdir -p /opt/bin
    fetch_artifact github/hub:v2.3.0-pre9 "linux-amd64.*.tgz" $PWD
    mv $(find -name hub -print -quit) /opt/bin
    export GITHUB_TOKEN=$GIT_TOKEN PATH=/opt/bin:$PATH
}

## fetch github-release
get_ghr() {
    mkdir -p /opt/bin
    fetch_artifact aktau/github-release ".*linux-amd64.*.bz2" $PWD
    mv $(find -name github-release -print -quit 2>/dev/null) /opt/bin
    export GITHUB_TOKEN=$GIT_TOKEN PATH=/opt/bin:$PATH
}

install_glib() {
    mount -o remount,ro /proc &>/dev/null
    ## GLIB
    GLIB_VERSION=$(last_version sgerrand/alpine-pkg-glibc)
    wget -q -O $1/etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub
    wget -q https://github.com/sgerrand/alpine-pkg-glibc/releases/download/$GLIB_VERSION/glibc-$GLIB_VERSION.apk
    if [ -n "$1" ]; then
        apk --root $1 add glibc-$GLIB_VERSION.apk
    else
        apk add glibc-$GLIB_VERSION.apk
    fi
    rm glibc-$GLIB_VERSION.apk
    mount -o remount,rw /proc &>/dev/null
}

usr_bind_rw() {
    if ! (cat /proc/mounts | grep -qE "\s/usr\s.*\s,?rw,?"); then
        os=$(ostree admin status | awk '/\*/{print $2}')
        dpl=$(ostree admin status | awk '/\*/{print $3}')
        mount -o bind,rw /ostree/deploy/${os}/deploy/${dpl}/usr /usr
    fi
}
## routing to add packages over existing tree
## checkout the trunk using hardlinks
#rm -rf ${ref}
#ostree checkout --repo=${repo_local} --union -H ${ref} ${ref}
### mount ro
#modprobe -q fuse
### overlay over the checkout to narrow pkg files
#rm -rf work ${pkg} over
#mkdir -p work ${pkg} over
#prepare_checkout ${ref}
#mount -t overlay -o lowerdir=${ref},workdir=work,upperdir=${pkg} none over
#apkc over add ${pkg}
### copy new files over read-only base checkout
#cp -an ${pkg}/* ${ref}-ro/
#fusermount -u ${ref}-ro/
