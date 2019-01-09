#!/bin/bash

# This script is used in Circl-CI to check that PRs do not add obvious
# flake8 violations. It relies on two things:
#   - find common ancestor between branch and
#     aif360-learn/aif360-learn remote
#   - run flake8 --diff on the diff between the branch and the common
#     ancestor
#
# Additional features:
#   - the line numbers in Travis match the local branch on the PR
#     author machine.
#   - ./build_tools/travis/flake8_diff.sh can be run locally for quick
#     turn-around

set -e
# pipefail is necessary to propagate exit codes
set -o pipefail

PROJECT=aif360-learn/aif360-learn
PROJECT_URL=https://github.com/$PROJECT.git

# Find the remote with the project name (upstream in most cases)
REMOTE=$(git remote -v | grep $PROJECT | cut -f1 | head -1 || echo '')

# Add a temporary remote if needed. For example this is necessary when
# Travis is configured to run in a fork. In this case 'origin' is the
# fork and not the reference repo we want to diff against.
if [[ -z "$REMOTE" ]]; then
    TMP_REMOTE=tmp_reference_upstream
    REMOTE=$TMP_REMOTE
    git remote add $REMOTE $PROJECT_URL
fi

echo "Remotes:"
echo '--------------------------------------------------------------------------------'
git remote --verbose

# Travis does the git clone with a limited depth (50 at the time of
# writing). This may not be enough to find the common ancestor with
# $REMOTE/master so we unshallow the git checkout
if [[ -a .git/shallow ]]; then
    echo -e '\nTrying to unshallow the repo:'
    echo '--------------------------------------------------------------------------------'
    git fetch --unshallow
fi

# we need to find the common
# ancestor between $LOCAL_BRANCH_REF and $REMOTE/master
if [[ -z "$COMMIT_RANGE" ]]; then
    if [[ -z "$LOCAL_BRANCH_REF" ]]; then
        LOCAL_BRANCH_REF=$(git rev-parse --abbrev-ref HEAD)
    fi
    echo -e "\nLast 2 commits in $LOCAL_BRANCH_REF:"
    echo '--------------------------------------------------------------------------------'
    git --no-pager log -2 $LOCAL_BRANCH_REF

    REMOTE_MASTER_REF="$REMOTE/master"
    # Make sure that $REMOTE_MASTER_REF is a valid reference
    echo -e "\nFetching $REMOTE_MASTER_REF"
    echo '--------------------------------------------------------------------------------'
    git fetch $REMOTE master:refs/remotes/$REMOTE_MASTER_REF
    LOCAL_BRANCH_SHORT_HASH=$(git rev-parse --short $LOCAL_BRANCH_REF)
    REMOTE_MASTER_SHORT_HASH=$(git rev-parse --short $REMOTE_MASTER_REF)

    COMMIT=$(git merge-base $LOCAL_BRANCH_REF $REMOTE_MASTER_REF) || \
        echo "No common ancestor found for $(git show $LOCAL_BRANCH_REF -q) and $(git show $REMOTE_MASTER_REF -q)"

    if [ -z "$COMMIT" ]; then
        exit 1
    fi

    COMMIT_SHORT_HASH=$(git rev-parse --short $COMMIT)

    echo -e "\nCommon ancestor between $LOCAL_BRANCH_REF ($LOCAL_BRANCH_SHORT_HASH)"\
         "and $REMOTE_MASTER_REF ($REMOTE_MASTER_SHORT_HASH) is $COMMIT_SHORT_HASH:"
    echo '--------------------------------------------------------------------------------'
    git --no-pager show --no-patch $COMMIT_SHORT_HASH

    COMMIT_RANGE="$COMMIT_SHORT_HASH..$LOCAL_BRANCH_SHORT_HASH"

    if [[ -n "$TMP_REMOTE" ]]; then
        git remote remove $TMP_REMOTE
    fi

else
    echo "Got the commit range from Travis: $COMMIT_RANGE"
fi

echo -e '\nRunning flake8 on the diff in the range' "$COMMIT_RANGE" \
     "($(git rev-list $COMMIT_RANGE | wc -l) commit(s)):"
echo '--------------------------------------------------------------------------------'

# We need the following command to exit with 0 hence the echo in case
# there is no match
MODIFIED_FILES="$(git diff --name-only $COMMIT_RANGE | \
                     grep -v 'doc/sphinxext/sphinx_gallery' || echo "no_match")"

check_files() {
    files="$1"
    shift
    options="$*"
    if [ -n "$files" ]; then
        # Conservative approach: diff without context (--unified=0) so that code
        # that was not changed does not create failures
        git diff --unified=0 $COMMIT_RANGE -- $files | flake8 --diff --show-source $options
    fi
}

if [[ "$MODIFIED_FILES" == "no_match" ]]; then
    echo "No file outside doc/sphinxext/sphinx_gallery has been modified"
else

    check_files "$(echo "$MODIFIED_FILES" | grep -v ^examples)"
    check_files "$(echo "$MODIFIED_FILES" | grep ^examples)" \
        --config ./examples/.flake8
fi
echo -e "No problem detected by flake8\n"
