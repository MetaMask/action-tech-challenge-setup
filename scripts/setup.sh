#!/usr/bin/env bash

set -e
set -o pipefail

readonly __USAGE__="Usage: ${0##*/} [--help] <github_username>"

readonly ORGANIZATION="MetaMaskHiring"
readonly TEMPLATE_REPO="${ORGANIZATION}/technical-challenge-shared-libraries"

function show_help {
    cat << EOF
${__USAGE__}

Setup a MetaMask Shared Libraries team technical challenge repository. This
script will create a new private GitHub repository for a candidate, prepare
tasks for them to work on, then invite them as a collaborator.

This script relies upon the GitHub CLI (\`gh\`). It assumes that \`gh\` is
installed and that authentication is setup.


    -h, -?, --help       Show this help message
    <github_username>    The username of the candidate

EOF
}

# Ensure that gh is present and authenticated
function check_auth {
  gh auth status 2>/dev/null
}

# Check whether "mislav/gh-repo-collab" is installed
function is_gh_repo_collab_installed {
  while IFS= read -r line; do 
    if [[ $line == 'mislav/gh-repo-collab' ]]; then
      return 0
    fi
  done < <(gh extension list | cut -f2)

  return 1
}

# Install "mislav/gh-repo-collab"
function install_gh_repo_collab {
  echo "Installing mislav/gh-repo-collab"
  gh extension install mislav/gh-repo-collab
}

# Get the name of the technical challenge repository
# $1 - The GitHub username of the candidate
function get_repo_name {
  local github_username="${1}"

  echo "${TEMPLATE_REPO}-${github_username}"
}

# Get the branch names for all template repository PRs
function get_pr_branches {
  gh pr list --repo "${TEMPLATE_REPO}" --json headRefName | jq -r '.[].headRefName'
}

# Create a new technical challenge repository
# $1 - The name of the new repository
# $2 - The GitHub username of the candidate
function create_repo {
  local repo_name="${1}"
  local github_username="${2}"

  local temporary_directory
  temporary_directory="$(mktemp -d)"

  gh repo clone "${TEMPLATE_REPO}" "${temporary_directory}"

  # set an arbirary remote name that does not conflict with 'origin'
  local remote_name
  remote_name='clone'

  gh repo create "${repo_name}" --private --source "${temporary_directory}" --remote "${remote_name}" --push

  # Sync additional branches needed for PRs
  local remote_branches
  mapfile -t remote_branches < <(get_pr_branches)

  for branch in "${remote_branches[@]}"; do
    (cd "${temporary_directory}" && git push "${remote_name}" "refs/remotes/origin/${branch}:refs/heads/${branch}")
  done

  rm -rf "${temporary_directory}"

  # Use '| cat' to suppress prompt for confirmation
  gh repo-collab add "${repo_name}" "${github_username}" --permission write | cat
}

function main {
  local github_username

  while :; do
    case $1 in
      -h|-\?|--help)
        show_help
        exit
        ;;
      *)
        if [[ -z $1 ]]; then
          break
        elif [[ -z $github_username ]]; then
          github_username="${1}"
        else
          printf "Unknown option: %s\\n" "${1}" >&2
          printf "%s\\n" "${__USAGE__}" >&2
          exit 1
        fi
    esac

    shift
  done

  if [[ -z $github_username ]]; then
    echo 'Missing required argument: <github_username>' >&2
    printf "%s\\n" "${__USAGE__}" >&2
    exit 1
  fi

  if ! check_auth; then
    # Repeat auth status check so that any errors get printed to the console
    gh auth status
    exit 1
  fi

  if ! is_gh_repo_collab_installed; then
    install_gh_repo_collab
  fi

  local repo_name
  repo_name="$(get_repo_name "${github_username}")"

  create_repo "${repo_name}" "${github_username}"
}

main "${@}"
