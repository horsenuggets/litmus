# litmus plans: the rest of 0.4.0

Last updated 2026-11-23. The cleanup is committed on `components`, phases 0 to 7. What's left is below, in order.

## 1. Fix what the Studio run found

- [x] **A lib error names the wrong line in Studio.** `Failures.spec`'s "points an error the lib raised at the test that caused it" fails in a plugin run. It expects `Lib.Failures.spec:25`, and gets `ReplicatedStorage.Litmus.Failure:90`.
  - **Cause:** `0616be7` moved the "called outside a spec" check from `test`, `group` and `after` into a local helper that raises at level 3. In Studio the position lands one frame too high. Lune counts the frames as written, so the standalone run passes.
  - **Same risk:** `report`'s `refuse` raises at level 3 through a helper, and `checkText` and `checkTone` add a second layer at level 4. No spec checks where a report refusal points.
  - **Chosen fix (option 1):** each public function raises at level 2 itself, sharing only its message. A new spec pins where a report refusal points.
  - **What changes:** only the position in front of a message. A failure's code line and position in the plugin and the CLI already come from the stack walk, and stay as they are.
  - **Done, not yet seen in Studio:** the standalone run passes with the new spec. The plugin run in the gate confirms it.
- [x] **A failure's message doesn't wrap in the results window.** It sits in the failure box above the code lines and runs off the edge, though `wrappedText` sets `TextWrapped`. Next check: whether the long message in `Interface.story.luau` wraps.
  - If it wraps there, the cause is in how the results window builds its rows.
  - If it doesn't, the cause is in `wrappedText`.
  - **Not seen again:** on 2026-11-23 a plugin run with long failure messages, with and without spaces, wrapped in the results window. No code changed for it.
- [x] Remove the second blank line in `plugin/Interface/Components/IconLine.luau`, left by step 46.

## 2. Gate

- [ ] `cargo test` in `cli/`, `lune run analyze`, and `litmus test --standalone`.
- [ ] In Studio:
  - a plugin run
  - a run with a test that fails on purpose
  - a standalone run shown in the plugin
  - `examples/standalone` with `--counts`
  - the story
  - the Core check, `loadstring(game.ReplicatedStorage.Tests.Core.Source)()`, with 26 cases
- [ ] The plugin UI phase 5 touched: the checkbox, the outlined button, collapsible rows and their fades, the ripple, the appendix's padding, the logos in both themes, and the Connected setting.
- [ ] The Linux job compiles and passes the Unix-only standalone tests.

## 3. Release 0.4.0

- [ ] Open the pull request from `components` to `main`, and merge once both jobs pass.
- [ ] Tag `v0.4.0` on `main` and push the tag.
- [ ] Move luau-crate and ecs-td to 0.4.0.
- [ ] On each machine: `git submodule update`, `rokit install`, `litmus plugin install`, and restart Studio. The protocol went from 2 to 3.

## 4. Make litmus public

- [ ] A README that covers:
  - what litmus is
  - its backends
  - installing it
  - a spec
  - `litmus.toml`
  - adapters and pieces
  - the Core check
  - `lune run analyze [--full]`, and that deleting `luau-cache` fetches newer definitions
- [ ] A LICENSE.
- [ ] `Cargo.toml` metadata: description, license, repository.
- [ ] Check the history for secrets.
- [ ] Keep the cloud job off pull requests from forks.
- [ ] Switch the repo to public.

## 5. After the release, in AnimeExpeditions

- [ ] Move its litmus submodule to `v0.4.0` and its Rokit pin to 0.4.0.
- [ ] Rename `litmus.Component` to `litmus.Piece` in `Tests/Adapter/Coverage/Pieces.luau:53`.
- [ ] Bring back the coverage floor through the `failure` that `results` returns.
- [ ] Add `litmus test --standalone` as a CI check.
- [ ] Push the branch and open the pull request. Merging is for the team and HorseNuggets to decide.
- [ ] Promote anything its adapter had to work around into the lib or the Lune adapter.
