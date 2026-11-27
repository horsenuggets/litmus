# Manages repository merge settings and required native checks on main and release.
# Supply TF_VAR_repository_owner and GITHUB_TOKEN when planning or applying.

terraform {
    required_version = ">= 1.7"

    cloud {
        workspaces {
            name = "litmus"
        }
    }

    required_providers {
        github = {
            source = "integrations/github"
            version = "~> 6.0"
        }
    }
}

variable "repository_owner" {
    description = "The account that owns the repository."
    type = string
    nullable = false

    validation {
        condition = length(trimspace(var.repository_owner)) > 0
        error_message = "Supply the repository owner through TF_VAR_repository_owner."
    }
}

provider "github" {
    owner = var.repository_owner
}

locals {
    repository_name = "litmus"
    native_checks = [
        "check-repository-settings",
        "native-tests-linux",
        "native-tests-macos",
        "native-tests-windows"
    ]
}

import {
    to = github_repository.repo
    id = "litmus"
}

resource "github_repository" "repo" {
    name = local.repository_name

    has_issues = true
    has_projects = false
    has_wiki = false

    allow_squash_merge = true
    allow_merge_commit = false
    allow_rebase_merge = false
    squash_merge_commit_title = "PR_TITLE"
    squash_merge_commit_message = "PR_BODY"
    delete_branch_on_merge = true

    lifecycle {
        prevent_destroy = true
        ignore_changes = [allow_auto_merge, description, homepage_url, topics, visibility]
    }
}

resource "github_branch" "release" {
    repository = github_repository.repo.name
    branch = "release"
    source_branch = "main"

    lifecycle {
        prevent_destroy = true
    }
}

resource "github_repository_ruleset" "protected" {
    for_each = toset(["main", "release"])
    depends_on = [github_branch.release]

    name = each.key
    repository = github_repository.repo.name
    target = "branch"
    enforcement = "active"

    conditions {
        ref_name {
            include = ["refs/heads/${each.key}"]
            exclude = []
        }
    }

    rules {
        deletion = true
        non_fast_forward = true

        pull_request {
            required_approving_review_count = 0
            dismiss_stale_reviews_on_push = true
        }

        required_status_checks {
            strict_required_status_checks_policy = true

            dynamic "required_check" {
                for_each = local.native_checks
                content {
                    context = required_check.value
                    integration_id = 15368
                }
            }
        }
    }
}
