# action-tech-challenge-setup

This is a GitHub action intended to prepare a technical challenge for a job candidate. This is meant for technical challenges created as private repositories, intended to simulate a real working environment. The private repository would be setup with issues to complete and pull requests to review, like on a real project.

## Requirements

To use this action, you must set the `GITHUB_TOKEN` environment variable to a personal access token that has permission to create the new repository and push commits to it. The owner of the personal access token must be a member of the organization provided via the "owner" parameter, and it must have the scopes `repo`, `workflow`, and `read:org`.

You will need to prepare an organization to create these repositories within as well. You may want it to be a separate free GitHub organization if you have a paid plan, to avoid being billed for each individual candidate as though they were a part of your team. This is provided as the `owner` input.

## Usage

## Setup a template repository

Start by creating a template repository for the technical challenge. This repository will be cloned to create the individual candidate technical challenge, including all git history, issues, and PRs. The candidate repository uses the template repository name as a prefix as well (the name will be `[template repository name]-[candidate username]`).

We recommend creating tasks for the candidate using issues, and creating code review tasks using pull requests.

For issues, the issue body, title, labels, and assignees are transferred. Note that the labels must be default labels however, and the assignees must already have access to the new repository (i.e. they must be members of the `owner` organization). Comments are not transferred.

The order of issues is preserved but the specific numbers are not. Issues are created first in the new repository as well (before pull requests), so they will have predictable numbers (e.g. the oldest issue will be `#1`).

For pull requests, the body and title are transferred, as well as any branches used by PRs. The target of each branch is assumed to be the `main` branch. Comments and reviews are not transferred.

## Create a "setup" repository

Next you will need to create a repository to help setup these challenges. This is where you'll add this action. This repository just serves as a place to keep this action and to document the internal process for technical challenges. The action can be run using a `workflow_dispatch` trigger.

For example, you could use a workflow like this:

```yaml
name: Setup tech challenge

on:
  workflow_dispatch:
    inputs:
      github-username:
        description: 'The GitHub username of the candidate'
        required: true

jobs:
  setup-repo:
    runs-on: ubuntu-latest
    steps:
      - name: Run the setup script
        uses: MetaMask/action-tech-challenge-setup@v1
        with:
          template-repository: MetaMask/example-technical-challenge
          github-username: ${{ inputs.github-username }}
```

### Running the action

The repository setup is automated with the "Setup tech challenge" GitHub Action. You can run this action by following these steps:

* Navigating to the "Actions" tab of this repository
* Select the "Setup tech challenge" workflow in the left sidebar
* Select the "Run workflow" dropdown on the right side of the screen
* Enter the candidate's _exact_ GitHub username in the GitHub username field 
* Click "Run workflow"

This will create the repository and invite the candidate as a collaborator. They should get an email from GitHub at this point, but we can send the repository link to them directly as well in case they miss the email.

## API

### Inputs

- `github-username`:
  The GitHub username of the candidate. This must match exactly.
- `template-repository`:
    The technical challenge template repository. The git history of this repository is cloned to create the new candidate technical challenge repository, along with any issues and PRs (excluding comments/reviews).
- `owner` (default: 'MetaMaskHiring'):
    The owner of the new candidate technical challenge repository. Typically we set this to a free GitHub organization that we control, so that we can maintain control of the repository and avoid being charged per-candidate.
