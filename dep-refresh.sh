#!/bin/bash
# set -eou pipefail

SCRIPT_ROOT=$(realpath $(dirname "${BASH_SOURCE[0]}"))
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

GITHUB_USER=${GITHUB_USER:-1gtm}
PR_BRANCH=ctrl2 # -$(date +%s)
COMMIT_MSG="Update deps"

REPO_ROOT=/tmp/stash-repo-refresher

API_REF=${API_REF:-1fb8e337}

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
    sed -i 's|appscode/gengo:release-1.25|appscode/gengo:release-1.29|g' Makefile
    sed -i 's/goconst,//g' Makefile
    sed -i 's|gcr.io/distroless/static-debian11|gcr.io/distroless/static-debian12|g' Makefile
    sed -i 's|debian:bullseye|debian:bookworm|g' Makefile
    sed -i 's|?= appscode/golang-dev:|?= ghcr.io/appscode/golang-dev:|g' Makefile

    pushd .github/workflows/ && {
        # update GO
        sed -i 's/Go\ 1.20/Go\ 1.21/g' *
        sed -i 's/go-version:\ ^1.20/go-version:\ ^1.21/g' *
        sed -i 's/go-version:\ 1.20/go-version:\ 1.21/g' *
        sed -i "s/go-version:\ '1.20'/go-version:\ '1.21'/g" *
        popd
    }

    if [ -f go.mod ]; then
        cat <<EOF > go.mod
module stash.appscode.dev/$name

EOF
        go mod edit \
            -require=stash.appscode.dev/apimachinery@${API_REF} \
            -require=kubedb.dev/apimachinery@v0.41.0 \
            -require=kubedb.dev/db-client-go@v0.0.10 \
            -require=gomodules.xyz/logs@v0.0.7 \
            -require=kmodules.xyz/client-go@v0.29.6 \
            -require=kmodules.xyz/resource-metadata@01f2d51a9f27c0f043e7d25f86a34fec97363b0b \
            -require=kmodules.xyz/go-containerregistry@v0.0.12 \
            -require=gomodules.xyz/password-generator@v0.2.9 \
            -require=go.bytebuilders.dev/license-verifier@v0.13.4 \
            -require=go.bytebuilders.dev/license-verifier/kubernetes@v0.13.4 \
            -require=go.bytebuilders.dev/license-proxyserver@31122ab825027d2495c9320b63d99660f1ca56be \
            -require=go.bytebuilders.dev/audit@9cf3195 \
            -require=github.com/cert-manager/cert-manager@v1.13.3 \
            -require=github.com/elastic/go-elasticsearch/v7@v7.15.1 \
            -require=go.mongodb.org/mongo-driver@v1.10.2 \
            -replace=github.com/Masterminds/sprig/v3=github.com/gomodules/sprig/v3@v3.2.3-0.20220405051441-0a8a99bac1b8 \
            -replace=sigs.k8s.io/controller-runtime=github.com/kmodules/controller-runtime@ac-0.17.0 \
            -replace=github.com/imdario/mergo=github.com/imdario/mergo@v0.3.6 \
            -replace=k8s.io/apiserver=github.com/kmodules/apiserver@ac-1.29.0 \
            -replace=k8s.io/kubernetes=github.com/kmodules/kubernetes@ac-1.29.0 \
            -require=github.com/docker/docker@v24.0.7+incompatible \
            -require=github.com/docker/cli@v24.0.7+incompatible

        # sed -i 's|NewLicenseEnforcer|MustLicenseEnforcer|g' `grep 'NewLicenseEnforcer' -rl *`
        go mod tidy
        go mod vendor
    fi
    [ -z "$2" ] || (
        echo "$2"
        $2 || true
        # run an extra make fmt because when make gen fails, make fmt is not run
        make fmt || true
    )
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
