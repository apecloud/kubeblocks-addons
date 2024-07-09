#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help                Display help
    -t, --type                Operation type
                                1) get base commit id
    -bn, --branch-name        The branch name
    -br, --base-branch        The base branch name
    -bc, --base-commit        The base commit id
EOF
}

parse_command_line() {
    while :; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit
                ;;
            -t|--type)
                if [[ -n "${2:-}" ]]; then
                    TYPE="$2"
                    shift
                fi
                ;;
            -bn|--branch-name)
                if [[ -n "${2:-}" ]]; then
                    BRANCH_NAME="$2"
                    shift
                fi
                ;;
            -br|--base-branch)
                if [[ -n "${2:-}" ]]; then
                    BASE_BRANCH="$2"
                    shift
                fi
                ;;
            -bc|--base-commit)
                if [[ -n "${2:-}" ]]; then
                    BASE_COMMIT="$2"
                    shift
                fi
                ;;
            *)
                break
                ;;
        esac

        shift
    done
}

set_base_commit_id() {
    if [[ ! -z "$BASE_COMMIT" ]]; then
        BASE_COMMIT_ID=$BASE_COMMIT
        return
    fi
    base_branch_commits="$( git rev-list $BASE_BRANCH -n 100 )"
    current_branch_commits="$( git rev-list $BRANCH_NAME -n 50 )"
    for base_commit_id in $( echo "$base_branch_commits" ); do
        found=false
        for cur_commit_id in $( echo "$current_branch_commits" ); do
            if [[ "$cur_commit_id" == "$base_commit_id" ]]; then
                BASE_COMMIT_ID=$base_commit_id
                found=true
                break
              fi
        done
        if [[ $found == true ]]; then
            break
        fi
    done
}

get_base_commit_id() {
    if [[ ! ("$BRANCH_NAME" == "main" || "$BRANCH_NAME" == "release-"* || "$BRANCH_NAME" == "releasing-"*) ]]; then
        set_base_commit_id
    fi
    echo "$BASE_COMMIT_ID"
}

main() {
    local TYPE=""
    local BRANCH_NAME=""
    local BASE_BRANCH=""
    local BASE_COMMIT=""
    local BASE_COMMIT_ID=HEAD^

    parse_command_line "$@"

    case $TYPE in
        1)
            get_base_commit_id
        ;;
        *)
            show_help
            break
        ;;
    esac
}

main "$@"
