#!/bin/bash

gem install travis
source functions.sh
user=untoreh
repo_rem=untoreh/trees
repo_rem_url="https://${GIT_USER}:${GIT_TOKEN}@github.com/$repo_rem"

handle_build() {
	## avoid non-tagged commits
	if [ -z "$TRAVIS_TAG" ]; then
		return
    fi
	## tags format is ${PKG}-YY.MM-X
	PKG=${TRAVIS_TAG/-*/}
	if [ -n "$PKG" ]; then
		BAS=$(cat $appslist | grep "$PKG" | head -1 | sed 's/.*://')
	fi
	## skip build if 
	## - the tag was not pushed by base repo (to rebuild all the dependents)
	## - pkg is already built on the latest base
	## - it is not older than 1 week
	pkg_d=$(last_release_date $repo_rem $PKG)
	bas_d=$(last_release_date $user/$BAS)
	week_old=$(release_older_than $pkg_d "7 days ago")
	if [ "$PKG" != "$BAS" -a $bas_d -le $pkg_d -a ! "$week_old" ]; then
		printc "$PKG was recently built."
		TRAVIS_JOB_NUMBER=${TRAVIS_JOB_NUMBER:-$TRAVIS_BUILD_NUMBER}
		travis cancel $TRAVIS_JOB_NUMBER --no-interactive -t $TRAVIS_TOKEN
		sleep 3600
	fi
	## if the tag is a base, retag for each app beloning to such base and exit
	## if there is no prefix (both PKG and BAS are empty) all apps get retagged (grep "")
	if [ "$PKG" = "$BAS" ]; then
		for a in $(cat $appslist | grep "$BAS"); do
			tag_prefix=${a/:*/}
			newtag=$(md)
			git tag ${tag_prefix}-${newtag} && git push --tags $repo_rem_url
		done
		travis cancel $TRAVIS_JOB_NUMBER --no-interactive -t $TRAVIS_TOKEN
		sleep 3600
	fi
	## if the event is a cron or commit is not app-prefixed we push a new tag for each app and exit
	if [ "$TRAVIS_EVENT_TYPE" = cron -a -z "$PKG" ]; then
		for a in $(cat $appslist); do
			tag_prefix=${a/:*/}
			newtag=$(md)
			git tag ${tag_prefix}-${newtag} && git push --tags $repo_rem_url
		done
		travis cancel $TRAVIS_JOB_NUMBER --no-interactive -t $TRAVIS_TOKEN
		sleep 3600
	fi
}

handle_deploy() {
	## if no changes where made to the tree skip deployment
	if [ $(cat file.up | grep "$PKG") ]; then
		travis cancel $TRAVIS_JOB_NUMBER --no-interactive -t $TRAVIS_TOKEN
		sleep 3600
	fi
}

handle_tags() {
	## since a build has been deployed update the static tag
	git symbolic-ref refs/tags/${PKG} refs/tags/$TRAVIS_TAG
	git push --tags --force $repo_rem_url
	fetch_artifact github/hub:2.3.0-pre9 "linux-amd64.*.tgz" $PWD
	GITHUB_TOKEN=$GIT_TOKEN
	hub*/bin/hub release edit "$TRAVIS_TAG" -m "" "${PKG}"
}
