#!/bin/bash
# set -eou pipefail

SCRIPT_ROOT=$(realpath $(dirname "${BASH_SOURCE[0]}"))
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

GITHUB_USER=${GITHUB_USER:-1gtm}
PR_BRANCH=generic-repo-refresher # -$(date +%s)
COMMIT_MSG="Update repository config"

REPO_ROOT=/tmp/generic-repo-refresher

refresh() {
    echo "refreshing repository: $1"
    rm -rf $REPO_ROOT
    mkdir -p $REPO_ROOT
    pushd $REPO_ROOT
    git clone --no-tags --no-recurse-submodules --depth=1 https://${GITHUB_USER}:${GITHUB_TOKEN}@$1.git
    cd $(ls -b1)
    git checkout -b $PR_BRANCH
    sed -i 's/busybox:1.31.1/busybox:latest/g' Makefile
    sed -i 's/alpine:3.11/alpine:latest/g' Makefile
    sed -i 's/alpine:3.10/alpine:latest/g' Makefile
    sed -i 's/debian:stretch/debian:buster/g' Makefile
    sed -i 's/gcr.io\/distroless\/base/gcr.io\/distroless\/base-debian10/g' Makefile
    sed -i 's/gcr.io\/distroless\/base-debian10-debian10/gcr.io\/distroless\/base-debian10/g' Makefile
    sed -i 's/gcr.io\/distroless\/static/gcr.io\/distroless\/static-debian10/g' Makefile
    sed -i 's/gcr.io\/distroless\/static-debian10-debian10/gcr.io\/distroless\/static-debian10/g' Makefile
    sed -i 's/chart-testing:v3.0.0-rc.1/chart-testing:v3.0.0/g' Makefile
    sed -i 's/?=\ 1.14/?=\ 1.15/g' Makefile
    pushd .github/workflows/
    sed -i 's/Go\ 1.14/Go\ 1.15/g' *
    sed -i 's/go-version:\ 1.14/go-version:\ 1.15/g' *
    sed -i 's/go-version:\ ^1.14/go-version:\ ^1.15/g' *
    sed -i 's/release-automaton\/releases\/download\/v0.0.27\//release-automaton\/releases\/download\/v0.0.28\//g' *
    sed -i 's/hugo-tools\/releases\/download\/v0.2.16\//hugo-tools\/releases\/download\/v0.2.18\//g' *
    sed -i 's/hugo-tools\/releases\/download\/v0.2.17\//hugo-tools\/releases\/download\/v0.2.18\//g' *
    popd
    [ -z "$2" ] || (
        echo "$2"
        $2 || true
    )
    git add --all
    if git diff --exit-code -s HEAD; then
        echo "Repository $1 is up-to-date."
    else
        if [[ "$1" == *"stashed"* ]]; then
            git commit -a -s -m "$COMMIT_MSG" -m "/cherry-pick"
        else
            git commit -a -s -m "$COMMIT_MSG"
        fi
        git push -u origin $PR_BRANCH -f
        hub pull-request \
            --labels automerge \
            --message "$COMMIT_MSG" \
            --message "Signed-off-by: $(git config --get user.name) <$(git config --get user.email)>" || true
        # gh pr create \
        #     --base master \
        #     --fill \
        #     --label automerge \
        #     --reviewer tamalsaha
    fi
    popd
}

if [ "$#" -ne 1 ]; then
    echo "Illegal number of parameters"
    echo "Correct usage: $SCRIPT_NAME <path_to_repos_list>"
    exit 1
fi

if [ -x $GITHUB_TOKEN ]; then
    echo "Missing env variable GITHUB_TOKEN"
    exit 1
fi

# ref: https://linuxize.com/post/how-to-read-a-file-line-by-line-in-bash/#using-file-descriptor
while IFS=, read -r -u9 repo cmd; do
    if [ -z "$repo" ]; then
        continue
    fi
    refresh "$repo" "$cmd"
    echo "################################################################################"
done 9<$1
