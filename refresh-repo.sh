#!/bin/bash
# set -eou pipefail

SCRIPT_ROOT=$(realpath $(dirname "${BASH_SOURCE[0]}"))
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

OLD_VER=0.17.1
NEW_VER=0.17.3

GITHUB_USER=${GITHUB_USER:-1gtm}
PR_BRANCH=rv0131 # -$(date +%s)
# COMMIT_MSG="Use restic ${NEW_VER}"
COMMIT_MSG="Revert to restic 0.17.3"

REPO_ROOT=/tmp/stash-updater

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
    cd $(ls -b1)
    git checkout -b $PR_BRANCH
    # sed -i "s|github.com/restic/restic|github.com/stashed/restic|g" Dockerfile.in
    # sed -i "s|github.com/restic/restic|github.com/stashed/restic|g" Dockerfile.dbg
    # sed -i "s|github.com/restic/restic|github.com/stashed/restic|g" Dockerfile.test || true
    sed -i "s|github.com/stashed/restic|github.com/restic/restic|g" Dockerfile.in
    sed -i "s|github.com/stashed/restic|github.com/restic/restic|g" Dockerfile.dbg
    sed -i "s|github.com/stashed/restic|github.com/restic/restic|g" Dockerfile.test || true
    sed -i "s|RESTIC_VER\([[:space:]]*\):= ${OLD_VER}|RESTIC_VER\1:= ${NEW_VER}|g" Makefile
    sed -i 's/?=\ 1.18/?=\ 1.19/g' Makefile
    # sed -i "s|strng{\"stash-enterprise\"}|string{\"stash-enterprise\",\ \"kubedb-ext-stash\"}|g" pkg/root.go

    pushd .github/workflows/ && {
        # update GO
        sed -i 's/Go\ 1.18/Go\ 1.19/g' *
        sed -i 's/go-version:\ ^1.18/go-version:\ ^1.19/g' *
        popd
    }

    # if [ -f go.mod ]; then
    #     sed -i "s|go 1.12|go 1.17|g" go.mod
    #     sed -i "s|go 1.13|go 1.17|g" go.mod
    #     sed -i "s|go 1.14|go 1.17|g" go.mod
    #     sed -i "s|go 1.15|go 1.17|g" go.mod
    #     sed -i "s|go 1.16|go 1.17|g" go.mod
    #     go mod edit \
    #         -require=kmodules.xyz/client-go@v0.24.5 \
    #         -require=kmodules.xyz/monitoring-agent-api@v0.24.0 \
    #         -require=kmodules.xyz/webhook-runtime@v0.24.0 \
    #         -require=kmodules.xyz/custom-resources@v0.24.1 \
    #         -require=kmodules.xyz/objectstore-api@v0.24.0 \
    #         -require=kmodules.xyz/offshoot-api@v0.24.2 \
    #         -require=gomodules.xyz/x@v0.0.14 \
    #         -require=gomodules.xyz/logs@v0.0.6 \
    #         -require=k8s.io/kube-openapi@v0.0.0-20220328201542-3ee0da9b0b42 \
    #         -require=kmodules.xyz/resource-metadata@v0.12.5 \
    #         -replace=github.com/Masterminds/sprig/v3=github.com/gomodules/sprig/v3@v3.2.3-0.20220405051441-0a8a99bac1b8 \
    #         -require=gomodules.xyz/password-generator@v0.2.8 \
    #         -require=go.bytebuilders.dev/license-verifier@v0.11.0 \
    #         -require=go.bytebuilders.dev/license-verifier/kubernetes@v0.11.0 \
    #         -require=go.bytebuilders.dev/audit@v0.0.23 \
    #         -require=stash.appscode.dev/apimachinery@v0.22.0 \
    #         -require=go.mongodb.org/mongo-driver@v1.9.1 \
    #         -replace=sigs.k8s.io/controller-runtime=github.com/kmodules/controller-runtime@v0.12.2-0.20220603144237-6cd001896bf3 \
    #         -replace=github.com/imdario/mergo=github.com/imdario/mergo@v0.3.5 \
    #         -replace=k8s.io/apimachinery=github.com/kmodules/apimachinery@v0.24.2-rc.0.0.20220603191800-1c7484099dee \
    #         -replace=k8s.io/apiserver=github.com/kmodules/apiserver@v0.0.0-20220603223637-59dad1716c43 \
    #         -replace=k8s.io/kubernetes=github.com/kmodules/kubernetes@v1.25.0-alpha.0.0.20220603172133-1c9d09d1b3b8
    #     go mod tidy
    #     go mod vendor
    # fi
    [ -z "$2" ] || (
        echo "$2"
        $2 || true
        # always run make fmt incase make gen fmt fails
        make fmt || true
    )
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
