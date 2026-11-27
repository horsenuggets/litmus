mock_provider "github" {}

override_resource {
    target = github_repository.repo
}

variables {
    repository_owner = "example-owner"
}

run "protect_native_publication" {
    command = plan

    assert {
        condition = github_repository.repo.allow_squash_merge && !github_repository.repo.allow_merge_commit && !github_repository.repo.allow_rebase_merge && github_repository.repo.delete_branch_on_merge
        error_message = "Repository merges must be squash-only and delete merged branches."
    }

    assert {
        condition = github_branch.release.branch == "release" && github_branch.release.source_branch == "main"
        error_message = "Bootstrap the release branch from main before enforcing its protections."
    }

    assert {
        condition = toset(keys(github_repository_ruleset.protected)) == toset(["main", "release"])
        error_message = "Both main and release must have a protection ruleset."
    }

    assert {
        condition = alltrue([
            for branch, ruleset in github_repository_ruleset.protected :
            ruleset.enforcement == "active" && ruleset.target == "branch" && toset(ruleset.conditions[0].ref_name[0].include) == toset(["refs/heads/${branch}"]) && length(ruleset.bypass_actors) == 0
        ])
        error_message = "Branch protection must be active without bypass actors."
    }

    assert {
        condition = alltrue([
            for ruleset in github_repository_ruleset.protected :
            ruleset.rules[0].deletion && ruleset.rules[0].non_fast_forward && length(ruleset.rules[0].pull_request) == 1 && ruleset.rules[0].pull_request[0].required_approving_review_count == 0 && ruleset.rules[0].pull_request[0].dismiss_stale_reviews_on_push
        ])
        error_message = "Protected branches require a pull request and block deletion and force pushes."
    }

    assert {
        condition = alltrue([
            for branch, ruleset in github_repository_ruleset.protected :
            ruleset.rules[0].required_status_checks[0].strict_required_status_checks_policy && toset([
                for check in ruleset.rules[0].required_status_checks[0].required_check : check.context
                ]) == toset(concat(["check-release-helpers", "check-repository-settings", "native-tests-linux", "native-tests-macos", "native-tests-windows"], branch == "release" ? ["check-release-contract"] : [])) && alltrue([
                for check in ruleset.rules[0].required_status_checks[0].required_check : check.integration_id == 15368
            ])
        ])
        error_message = "Every native and helper check must pass, with the release contract required only on release."
    }
}
