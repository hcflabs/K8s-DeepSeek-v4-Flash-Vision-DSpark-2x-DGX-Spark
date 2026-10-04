# Releasing the chart

Every release operation runs in GitHub Actions — the version bump, the
changelog, the tag, the OCI push and the GitHub Release. Nothing is released
from a workstation, and no step of a release is done by hand.

`Chart.yaml` has two version fields and they are independent:

| Field | Meaning | Managed by |
| --- | --- | --- |
| `version` | the chart artifact: the OCI tag, `helm pull --version`, a k3s `HelmChart`'s `spec.version` | the release workflow, derived from conventional commits |
| `appVersion` | the serving image the chart defaults to | by hand, tracks `image.tag` in `values.yaml` |

## Cutting a release

Actions -> **release** -> *Run workflow* -> pick a bump -> *Run*, or:

```bash
gh workflow run release.yml -f bump=auto     # auto | patch | minor | major
```

One job then does all of it:

1. derives the next version from the commits (`bump=auto`) or from the `bump`
   input;
2. refuses to continue if that version does not advance `chart/Chart.yaml`;
3. writes the version into `chart/Chart.yaml` (leaving `appVersion` alone);
4. prepends the new section to `chart/CHANGELOG.md`;
5. commits `chore(release): vX.Y.Z` and pushes the annotated tag `vX.Y.Z`;
6. lints, packages from `Chart.yaml`, and pushes the chart to
   `oci://ghcr.io/<owner>/charts`;
7. creates the GitHub Release, using the same changelog section as its notes.

Publishing happens in the same job as the bump on purpose: a tag pushed with the
default `GITHUB_TOKEN` does not trigger another workflow run.

### Re-running

Every step is idempotent, so re-running a release is safe:

| State on entry | What it does |
| --- | --- |
| version already bumped, changelog written, tag pushed | publishes only (a no-op if that already succeeded) |
| version bumped and changelog written, but the tag is missing | tags and publishes |
| nothing new since the last tag | publishes the current version; use the `bump` input for a real release |
| `chart/Chart.yaml` ahead of the last tag | fails loudly rather than publishing a lower version |

### The first release

No `v*` tag exists yet, so the workflow releases the version already in
`Chart.yaml` (`0.1.0`) rather than deriving one. Nothing special to do — just
run it.

## What bumps what

| Commit type | Bump |
| --- | --- |
| `feat:` | minor |
| breaking (`feat!:`, `BREAKING CHANGE:`) | major (minor while the major is 0) |
| `fix:`, `perf:`, `refactor:`, `style:`, `build:`, `revert:` | patch |
| `docs:`, `chore:`, `ci:`, `test:` | none — these do not change the artifact |

The `bump` input is a **minimum**: it cannot lower a bump the commits already
justify (a `feat:` still yields a minor when `patch` is selected), but it forces
a release when the commits alone would produce none. That is the escape hatch
for a chart change that was committed as `docs:`/`chore:`.

## Configuration

- `cliff.toml` — commit grouping, the changelog template, and the bump rules.
- `chart/CHANGELOG.md` — generated. Its header must stay identical to
  `[changelog] header` in `cliff.toml`: `--prepend` strips the header it knows
  about and rewrites it above the new section, so changing one means changing
  both. (git-cliff falls back to its own template when the config is missing,
  which mangles the header — the workflow refuses to run in that case.)
- `GIT_CLIFF_VERSION` in `.github/workflows/release.yml` pins the binary; the
  config was verified against that version.
