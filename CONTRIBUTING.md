# Contributing

Thanks for taking a look. This repository is a Kubernetes/k3s port of the
upstream Compose recipe; `README.md` covers what it deploys and `RELEASING.md`
covers how chart versions are cut.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md), and
contributions are accepted under the repository's [MIT license](LICENSE)
(inbound = outbound).

## Scope

In scope: the Helm chart, the Ansible playbooks, the scripts under `scripts/`,
CI, and documentation.

Out of scope — please raise these upstream instead:

| Topic | Where |
| --- | --- |
| the recipe, hotfixes and the serving image itself | [MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark) |
| model weights and model behaviour | the relevant Hugging Face model card |
| the k3s collection used to join nodes | [k3s-io/k3s-ansible](https://github.com/k3s-io/k3s-ansible) |

## Commit messages

Commits drive the release: `cliff.toml` derives the next chart version and the
changelog from them, so please use conventional commits.

| Prefix | Chart version effect |
| --- | --- |
| `feat:` | minor |
| `fix:`, `perf:`, `refactor:`, `style:`, `build:`, `revert:` | patch |
| `docs:`, `chore:`, `ci:`, `test:` | none |

A chart change committed as `docs:` or `chore:` publishes nothing, so use
`feat:`/`fix:` for changes to the chart itself. See `RELEASING.md`.

## Local checks

Run what CI runs before opening a pull request:

```bash
# chart renders and lints; it must also refuse to render without site values
helm lint chart -f chart/ci/test-values.yaml
helm template ci chart -f chart/ci/test-values.yaml > /dev/null

# shell
shellcheck -S warning chart/files/serve.sh chart/files/wait-for-worker.sh scripts/*.sh ansible/init-vault.sh

# embedded hotfix scripts parse (no docker needed)
scripts/check-anchors.sh

# the real anchor gate: dry-runs every hotfix against the pinned arm64 image.
# Needs docker and pulls ~9 GiB; also fetches the checkpoint's ~36 KB encoder.
scripts/check-anchors.sh --image ghcr.io/anemll/dspark-vllm-gx10:0.1.1

# workflows
# (CI runs actionlint; locally: brew install actionlint, then)
actionlint .github/workflows/*.yml

# ansible
cd ansible && ansible-playbook -i inventory.example.yml playbooks/site.yml --syntax-check
```

## Changing the hotfixes

`chart/files/hotfixes/` is vendored from upstream at a pinned commit, not
live-followed. If you re-vendor or add one:

1. follow the file→`patches/X` mapping and ordering rules in [`SYNC.md`](SYNC.md);
2. keep the gate and ordering in `chart/files/serve.sh` in the same position as
   the upstream Compose `command:` block;
3. map the gate to a value in `chart/values.yaml` and add it to the table in
   [`ENVS.md`](ENVS.md);
4. run `scripts/check-anchors.sh --image <image>` — an anchor that no longer
   matches must fail the pod, not degrade silently;
5. update the pinned SHA in `SYNC.md`.

Never edit a vendored file in place: the anchor check compares against the image,
and `SYNC.md` records what came from where.

## Please do not commit

- API keys, k3s join tokens, vault passwords, or `.vault_pass`;
- your cluster's addresses, hostnames, node names, or interface/device names
  (fabric addressing and weights paths must stay required-without-default);
- your checkpoint paths or a model id you did not intend to publish.

The `chart/ci/test-values.yaml` placeholders and the documentation-range
addresses in `ansible/inventory.example.yml` exist so that examples never carry
a real deployment's details — keep it that way.

## Pull requests

CI must be green (`chart` and `anchors`). The `anchors` job is the slow one: it
pulls the image and dry-runs every hotfix, so a failure there usually means an
anchor moved rather than a flake. If you changed the default image or any file
under `chart/files/hotfixes/`, expect it to be the deciding check.

Releases are cut by maintainers from the `release` workflow after merge; there is
nothing to do in a pull request to trigger one.
