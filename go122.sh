#!/bin/bash
# set -eou pipefail

SCRIPT_ROOT=$(realpath $(dirname "${BASH_SOURCE[0]}"))
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

GITHUB_USER=${GITHUB_USER:-1gtm}
PR_BRANCH=go122 # -$(date +%s)
COMMIT_MSG="Use Go 1.22"

REPO_ROOT=/tmp/stash-repo-refresher

API_REF=${API_REF:-c5efabadb}

repo_uptodate() {
    # gomodfiles=(go.mod go.sum vendor/modules.txt)
    gomodfiles=(go.sum vendor/modules.txt)
    changed=($(git diff --name-only))
    changed+=("${gomodfiles[@]}")
    # https://stackoverflow.com/a/28161520
    diff=($(echo ${changed[@]} ${gomodfiles[@]} | tr ' ' '\n' | sort | uniq -u))
    return ${#diff[@]}
}

refresh() {
    echo "refreshing repository: $1"
    rm -rf $REPO_ROOT
    mkdir -p $REPO_ROOT
    pushd $REPO_ROOT
    git clone --no-tags --no-recurse-submodules --depth=1 git@github.com:$1.git
    name=$(ls -b1)
    cd $name
    git checkout -b $PR_BRANCH

    sed -i 's/?=\ 1.20/?=\ 1.21/g' Makefile
    sed -i 's/?=\ 1.21/?=\ 1.22/g' Makefile
    sed -i 's|appscode/gengo:release-1.25|appscode/gengo:release-1.29|g' Makefile
    sed -i 's/goconst,//g' Makefile
    sed -i 's|gcr.io/distroless/static-debian11|gcr.io/distroless/static-debian12|g' Makefile
    sed -i 's|debian:bullseye|debian:bookworm|g' Makefile

    pushd .github/workflows/ && {
        # update GO
        sed -i 's/Go\ 1.20/Go\ 1.21/g' *
        sed -i 's/go-version:\ ^1.20/go-version:\ ^1.21/g' *
        sed -i 's/go-version:\ 1.20/go-version:\ 1.21/g' *
        sed -i "s/go-version:\ '1.20'/go-version:\ '1.21'/g" *

        sed -i 's/Go\ 1.21/Go\ 1.22/g' *
        sed -i 's/go-version:\ ^1.21/go-version:\ ^1.22/g' *
        sed -i 's/go-version:\ 1.21/go-version:\ 1.22/g' *
        sed -i "s/go-version:\ '1.21'/go-version:\ '1.22'/g" *
        popd
    }

    if [ -f go.mod ]; then
        go mod edit \
            -require=kmodules.xyz/client-go@v0.29.13 \
            -require=kmodules.xyz/resource-metadata@v0.18.2 \
            -require=gomodules.xyz/password-generator@v0.2.9 \
            -require=go.bytebuilders.dev/license-verifier@v0.14.0 \
            -require=go.bytebuilders.dev/license-verifier/kubernetes@v0.14.0 \
            -require=go.bytebuilders.dev/license-proxyserver@v0.0.9 \
            -require=go.bytebuilders.dev/audit@v0.0.33 \
            -require=golang.org/x/net@v0.23.0 \
            -require=github.com/golang/protobuf@v1.5.4 \
            -require=google.golang.org/protobuf@v1.33.0 \
            -require=github.com/docker/docker@v24.0.9+incompatible \
            -require=github.com/docker/cli@v24.0.9+incompatible

            # -replace=github.com/Masterminds/sprig/v3=github.com/gomodules/sprig/v3@v3.2.3-0.20220405051441-0a8a99bac1b8 \
            # -replace=sigs.k8s.io/controller-runtime=github.com/kmodules/controller-runtime@ac-0.17.0 \
            # -replace=github.com/imdario/mergo=github.com/imdario/mergo@v0.3.6 \
            # -replace=k8s.io/apiserver=github.com/kmodules/apiserver@ac-1.29.0 \
            # -replace=k8s.io/kubernetes=github.com/kmodules/kubernetes@ac-1.29.0 \
            # -require=github.com/docker/docker@v24.0.9+incompatible \
            # -require=github.com/docker/cli@v24.0.9+incompatible

        # sed -i 's|NewLicenseEnforcer|MustLicenseEnforcer|g' `grep 'NewLicenseEnforcer' -rl *`
        go mod tidy
        go mod vendor
    fi
    make fmt || true

    if repo_uptodate; then
        echo "Repository $1 is up-to-date."
    else
        git add --all
        if [[ "$1" == *"stashed"* ]]; then
            git commit -a -s -m "$COMMIT_MSG" -m "/cherry-pick"
        else
            git commit -a -s -m "$COMMIT_MSG"
        fi
        git push -u origin HEAD -f
        hub pull-request \
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
