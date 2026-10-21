---
name: update-distro
description: Update this nomad-distro-dev fork and its nomad-FAIR submodule from upstream FAIRmat, resolve the usual conflicts, keep the HZB plugin repos on their branches, re-sync uv and verify the plugins. Use when the user wants to update the distro, update/upgrade nomad or nomad-FAIR, pull upstream changes, or recover from a messy git pull or rebase in this repo.
---

# Update the Distro from Upstream

This repo is a fork with local commits. `origin` is usually stale; `upstream` (FAIRmat-NFDI) is the source of updates. **Never** use `git pull` here, and **never** run a blanket `git submodule update`. Use `git -C <path>` instead of `cd` for git commands. For `uv` commands you must `cd` into the project root (uv has no `-C` / `--project` flag).

## 0. Recover First if a Pull Went Wrong

```bash
git status            # look for "rebase in progress" or "merging"
git rebase --abort    # or: git merge --abort
git stash list        # a "WIP on main" stash made just before the pull holds the user's uncommitted work
```

Check `git config pull.rebase` is `false` in this repo.

If `git merge` fails with **"fatal: invalid commit position. commit-graph is likely corrupt"**, remove the corrupt graph and retry:

```bash
rm -f .git/objects/info/commit-graph
git merge --no-ff upstream/main
```

## 1. Preflight

- The superproject working tree must be clean (only submodule `+` markers and untracked files are OK). If not, ask the user whether to commit or stash. A stash must be re-applied in step 6.
- Record each plugin repo's branch and commit, so they can be restored if anything moves them:

```bash
for p in nomad-FAIR nomad-baseclasses nomad-hysprint nomad-tfsc-general; do
  echo "$p: branch=$(git -C packages/$p rev-parse --abbrev-ref HEAD) commit=$(git -C packages/$p rev-parse --short HEAD)"; done
```

  Some entries (e.g. `nomad-perovskite-solar-cells-database`, `nomad-plugins`) may not exist as directories — that is fine.

- Fetch and make a backup branch:

```bash
git fetch upstream
git branch backup/before-update-$(date +%F) main
git rev-list --left-right --count main...upstream/main   # local-only vs. new upstream commits
```

- Dry-run the merge to see conflicts:

```bash
git merge-tree --write-tree --name-only main upstream/main
```

## 2. Merge

Use `--no-commit` so you can resolve conflicts step by step:

```bash
git merge --no-ff --no-commit upstream/main
```

Typical conflicts and how to resolve them:

### `packages/nomad-FAIR`

Take upstream's pin. First confirm the local pin is an ancestor of upstream's:

```bash
UPSTREAM_PIN=$(git ls-tree upstream/main packages/nomad-FAIR | awk '{print $3}')
LOCAL_HEAD=$(git -C packages/nomad-FAIR rev-parse HEAD)
git -C packages/nomad-FAIR merge-base --is-ancestor $LOCAL_HEAD $UPSTREAM_PIN && echo "OK"
```

If not an ancestor, you must merge inside the submodule. If it IS an ancestor:

```bash
git -C packages/nomad-FAIR fetch origin
git -C packages/nomad-FAIR checkout $UPSTREAM_PIN
git add packages/nomad-FAIR
```

### `pyproject.toml`

Compare both sides against the merge base:

```bash
B=$(git merge-base main upstream/main)
git diff $B main -- pyproject.toml            # what we changed
git diff $B upstream/main -- pyproject.toml   # what upstream changed
```

**Resolution rules:**

1. **Dependencies**: Keep all local plugin entries (nomad-baseclasses, nomad-hysprint, etc.) AND add upstream's new deps (e.g. `nomad-gui>=2.0.0b2`). Keep our higher `nomad-lab` version pin if it exceeds upstream's.
2. **Workspace members**: Use upstream's `"packages/*"` glob. The old explicit list referenced non-existent directories (`nomad-plugins`, `nomad-perovskite-solar-cells-database`). A glob picks up only what exists.
3. **UV sources**: Keep local workspace sources AND add upstream's git-sourced deps (nomad-aitoolkit, nomad-porous-materials, perovskite-solar-cell-database, nomad-external-eln-integrations). These are in the merge base; don't drop them.
4. **Poe tasks**: Accept upstream's changes (e.g. `setup = ["docker", "config"]` dropping gui steps, `start-info` task added, cross-platform gui/gui-setup with switch cases).

Validate the result before committing:

```bash
python3 -I -c "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb')); print('TOML OK')" pyproject.toml
```

Stage and commit:

```bash
git add pyproject.toml
git commit -m "Merge upstream/main (N commits) into main: <conflict notes>"
```

## 3. Submodules

Update only nomad-FAIR:

```bash
git submodule update packages/nomad-FAIR
```

Then check `git submodule status`. If any HZB plugin repo was detached from the branch recorded in step 1, check it out again. A `+` prefix in the status output just means the plugin is newer than its pin. If the user wants it pinned, commit the pointer with `git add packages/<name>`.

## 4. Environment

```bash
cp uv.lock /tmp/uv.lock.before-update   # uv.lock is untracked
cd /home/a4864/code/nomad-distro-dev && uv sync
uv run --no-sync python -c "from nomad.config import config; config.load_plugins(); print(len(config.plugins.entry_points.options), 'plugins loaded')"
```

A successful sync prints "Resolved N packages" and "Checked N packages". The plugin count should be ~46.

## 5. Verify Plugins Against the New nomad-lab

### Pre-test config fix

**`packages/nomad-baseclasses/nomad.yaml`** uses the old plugin config format. New nomad-lab requires `plugins.entry_points.include` as a list. If tests fail with:

```
pydantic_core._pydantic_core.ValidationError: ... Input should be a valid list ... input_value='schemas/baseclasses'
```

Fix the file to use the new format:

```yaml
plugins:
  entry_points:
    include:
      - "schemas/baseclasses"
    options:
      schemas/baseclasses:
        python_package: baseclasses
```

### Running tests

Run each installed plugin's tests from its own directory with the workspace venv:

```bash
cd packages/nomad-hysprint && timeout 300 ../../.venv/bin/python -m pytest -q tests 2>&1 | tail -5
```

For **nomad-tfsc-general**, exclude hysprint's entry points via a temporary config. Otherwise the hysprint parser claims tfsc's Excel files and tests fail for unrelated reasons:

```bash
cat > /tmp/nomad-tfsc-test.yaml << 'EOF'
plugins:
  entry_points:
    exclude: ["nomad_hysprint.parsers:hysprint_parser", "nomad_hysprint.parsers:hysprint_experiment_parser"]
EOF
cd packages/nomad-tfsc-general && NOMAD_CONFIG=/tmp/nomad-tfsc-test.yaml timeout 300 ../../.venv/bin/python -m pytest -q tests 2>&1 | tail -5
```

If a plugin is not installed in the current workspace (tfsc-general is commented out of deps), install it temporarily:

```bash
uv pip install --no-deps -e packages/nomad-tfsc-general
# ... run tests ...
uv pip uninstall nomad-tfsc-general && uv sync
```

### Known pre-existing test failures

- **`nomad-baseclasses/tests/test_schema.py`**: References `nomadschemaexample.ExampleSection` which does not exist in the source. This test has always failed — it is NOT caused by the update.

### Check What Changed in nomad-FAIR

Look for removed config options, removed APIs, and infrastructure changes:

```bash
git -C packages/nomad-FAIR diff <old-pin> <new-pin> --stat
git -C packages/nomad-FAIR log --oneline <old-pin>..<new-pin> | grep -iE "break|remov|deprecat|migrat|config|elastic|mongo|pydantic"
```

Then grep the HZB plugins' `src/` and their `nomad.yaml` files for anything that was removed.

### Plugin compatibility audit

```bash
# NOTE: This script does not currently exist in the repo. Skip this step unless
# /nomad-plugin-modernize is installed.
# python3 -I .cline/skills/nomad-plugin-modernize/scripts/audit_plugin.py \
#   packages/nomad-baseclasses packages/nomad-hysprint packages/nomad-tfsc-general
```

## 6. Restore Work and Push

- If a stash was made in step 1, run `git stash apply` (not `pop`), check the result, then drop the stash.
- Before pushing, check for large files:

```bash
git diff --stat origin/main..main
```

Look for anything unexpected such as installers or `.deb` files. Removing one from unpushed history needs a rewrite. Rewrite **only your own commits**, because rewriting upstream's signed commits changes their hashes:

```bash
git filter-branch --index-filter 'git rm --cached --quiet --ignore-unmatch <file>' -- main --not origin/main --remotes=upstream
```

Then confirm `git rev-list --left-right --count main...upstream/main` still shows 0 on the right.

- Ask the user before pushing. HTTPS has no credentials here, so push over SSH:

```bash
git push git@github.com:zNuu/nomad-distro-dev main:main
git update-ref refs/remotes/origin/main main
```

- Once the push is confirmed, delete the backup branch if the user wants.

## 7. Report

Tell the user:

- Which upstream PRs and which nomad-FAIR commit range came in
- How each conflict was resolved
- The test results for each plugin
- Anything in the nomad-FAIR changes that needs action in their plugins or `nomad.yaml`
