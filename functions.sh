#!/bin/bash

cn="\033[1;32;40m"
cf="\033[0m"
printc(){
        echo -e "${cn}$@${cf}"
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

## $1 repo
last_release() {
    wget -qO- https://api.github.com/repos/${1}/releases/latest | \
    awk '/tag_name/ { print $2 }' | head -1 | sed -r 's/",?//g'
 }

## $1 repo
## $2 artifact name
fetch_artifact() {
    rm release -rf
    mkdir release
    art_url=$(wget -qO- https://api.github.com/repos/${1}/releases | \
     grep browser_download_url | grep ${2} | head -n 1 | cut -d '"' -f 4)
    wget ${art_url} -O- | tar xz -C release/
}
