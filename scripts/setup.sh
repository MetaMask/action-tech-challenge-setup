#!/usr/bin/env bash

set -e
set -o pipefail

readonly __USAGE__="Usage: ${0##*/} [options] <template_repository> <owner> <github_username>"

function show_help {
    cat << EOF
${__USAGE__}

Setup a technical challenge repository using the given template. This script
will create a new private GitHub repository for a candidate, prepare tasks for
them to work on, then invite them as a collaborator.

This script relies upon the GitHub CLI (\`gh\`). It assumes that \`gh\` is
installed and that authentication is setup.


    -h, -?, --help         Show this help message
    -s, --skip-invite      Skip the step where the candidate is invited as a
                           collaborator
    <template_repository>  The template repository for the technical challenge
                           given in the format "[owner]/[repository name]"
                           (for example: 'MetaMaskHiring/technical-challenge')
    <owner>                The owner of the new repository (typically a free
                           GitHub organization)
    <github_username>      The username of the candidate

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
# $1 - The template repository
# $2 - The owner of the new technical challenge repository
# $3 - The GitHub username of the candidate
function get_repo_name {
  local template_repository="${1}"
  local owner="${2}"
  local github_username="${3}"

  echo "${owner}/${template_repository#*/}-${github_username}"
}

# Get the branch names for all template repository PRs
# $1 - The template repository
function get_pr_branches {
  local template_repository="${1}"

  gh pr list --repo "${template_repository}" --json headRefName | jq -r '.[].headRefName'
}

# Create a new technical challenge repository
# $1 - The template repository
# $2 - The name of the new repository
# $3 - The GitHub username of the candidate
function create_repo {
  local template_repository="${1}"
  local repo_name="${2}"
  local github_username="${3}"

  local temporary_directory
  temporary_directory="$(mktemp -d)"

  gh repo clone "${template_repository}" "${temporary_directory}"

  # set an arbirary remote name that does not conflict with 'origin'
  local remote_name
  remote_name='clone'

  gh repo create "${repo_name}" --private --source "${temporary_directory}" --remote "${remote_name}" --push

  # If running from a GitHub Action, set authorization header explicitly so that the later 'git push' step works
  # Source: <https://github.com/actions/checkout/blob/f095bcc56b7c2baf48f3ac70d6d6782f4f553222/src/git-auth-helper.ts>
  if [[ -n $GITHUB_TOKEN ]]; then
    echo "GitHub Actions environment detected, configuring Authorization header"
    local encoded_token
    encoded_token="$(echo -n "x-access-token:${GITHUB_TOKEN}" | base64)"
    (cd "${temporary_directory}" && git config "http.https://github.com/.extraHeader" "Authorization: Basic ${encoded_token}")
  fi

  # Sync additional branches needed for PRs
  local remote_branches
  mapfile -t remote_branches < <(get_pr_branches "${template_repository}")

  for branch in "${remote_branches[@]}"; do
    (cd "${temporary_directory}" && git push "${remote_name}" "refs/remotes/origin/${branch}:refs/heads/${branch}")
  done

  rm -rf "${temporary_directory}"
}

# Invite the candidate to collaborate on the new repository
# $1 - The name of the new repository
# $2 - The GitHub username of the candidate
function invite_candidate {
  local repo_name="${1}"
  local github_username="${2}"

  # Use '| cat' to suppress prompt for confirmation
  gh repo-collab add "${repo_name}" "${github_username}" --permission write | cat
}

# Output a list of all issues in the template repository. Each entry will be a
# JSON string that includes the issue number, title, body, labels, and
# assignees. The list will be sorted by issue number (ascending).
# $1 - The template repository
function get_issues {
  local template_repository="${1}"

  gh issue list --repo "${template_repository}" --json number,title,body,labels,assignees | jq -c 'sort_by(.number) | .[]'
}

# Output a JSON list of all pull requests in the template repository. Each
# entry will be a JSON string that includes the PR number, title, body, and the
# branch name (under the key 'headRefName'). The list will be sorted by PR
# number (ascending).
# $1 - The template repository
function get_prs {
  local template_repository="${1}"

  gh pr list --repo "${template_repository}" --json number,title,body,headRefName | jq -c 'sort_by(.number) | .[]'
}



# Create issues in the technical challenge repository
# $1 - The template repository
# $2 - The name of the new repository
function add_issues {
  local template_repository="${1}"
  local repo_name="${2}"

  local issues
  mapfile -t issues < <(get_issues "${template_repository}")

  local body
  local title
  local labels
  local assignees

  for issue in "${issues[@]}"; do
    title="$(jq -r '.title' <<< "${issue}")"
    body="$(jq -r '.body' <<< "${issue}")"
    labels="$(jq -r '.labels | map(.name) | join(",")' <<< "${issue}")"
    assignees="$(jq -r '.assignees | map(.login) | join(",")' <<< "${issue}")"
    gh issue create --repo "${repo_name}" --title "${title}" --body "${body}"  --label "${labels}" --assignee "${assignees}"
  done
}

# Create pull requests in the technical challenge repository
# $1 - The template repository
# $2 - The name of the new repository
function add_prs {
  local template_repository="${1}"
  local repo_name="${2}"

  local prs
  mapfile -t prs < <(get_prs "${template_repository}")

  local body
  local title
  local branch_name

  for pr in "${prs[@]}"; do
    body="$(jq -r '.body' <<< "${pr}")"
    title="$(jq -r '.title' <<< "${pr}")"
    branch_name="$(jq -r '.headRefName' <<< "${pr}")"
    gh pr create --repo "${repo_name}" --head "${branch_name}" --title "${title}" --body "${body}"
  done
}

function main {
  local template_repository
  local owner
  local github_username
  local invite='true'

  while :; do
    case $1 in
      -h|-\?|--help)
        show_help
        exit
        ;;
      -s|--skip-invite)
        invite='false'
        ;;
      *)
        if [[ -z $1 ]]; then
          break
        elif [[ -z $template_repository ]]; then
          template_repository="${1}"
        elif [[ -z $owner ]]; then
          owner="${1}"
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

  if [[ -z $template_repository ]]; then
    echo 'Missing required argument: <template_repository>' >&2
    printf "%s\\n" "${__USAGE__}" >&2
    exit 1
  elif [[ -z $owner ]]; then
    echo 'Missing required argument: <owner>' >&2
    printf "%s\\n" "${__USAGE__}" >&2
    exit 1
  elif [[ -z $github_username ]]; then
    echo 'Missing required argument: <github_username>' >&2
    printf "%s\\n" "${__USAGE__}" >&2
    exit 1
  fi

  if ! check_auth; then
    # Repeat auth status check so that any errors get printed to the console
    gh auth status
    exit 1
  fi

  if [[ $invite == 'true' ]] && ! is_gh_repo_collab_installed; then
    install_gh_repo_collab
  fi

  local repo_name
  repo_name="$(get_repo_name "${template_repository}" "${owner}" "${github_username}")"

  create_repo "${template_repository}" "${repo_name}" "${github_username}"

  if [[ $invite == 'true' ]]; then
    invite_candidate "${repo_name}" "${github_username}"
  fi

  # Add issues first because the template includes issue references in issue
  # and PR bodies.
  add_issues "${template_repository}" "${repo_name}"

  add_prs "${template_repository}" "${repo_name}"
}

main "${@}"
