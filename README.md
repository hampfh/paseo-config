# paseo-config

Shared Paseo configuration for `deathstar` and `hampusstrawberry`.

This is a starter repository, not a snapshot of either machine. It contains no credentials, copied daemon state, or active Hub triggers. Creating or cloning it does not change a running daemon.

## Layout

- `daemon/shared.json`: common daemon settings, taken from `hampusstrawberry`'s `~/.paseo/config.json` on 2026-11-05 minus host-specific keys (`daemon.listen`, `daemon.relay`, `daemon.cors`). Not yet reviewed against `deathstar`.
- `hosts/overrides.example.json`: template for machine-specific settings. Copy it to `hosts/deathstar.local.json` or `hosts/hampusstrawberry.local.json`; these local files are ignored by Git.
- `.paseo/triggers/`: version-controlled Hub triggers, separate from local daemon settings.

## Use on another machine

```sh
git clone git@github.com:hampfh/paseo-config.git ~/dev/paseo-config
cd ~/dev/paseo-config
```

Keep a backup of the machine's existing `~/.paseo/config.json` before editing. If the machine uses a custom `PASEO_HOME`, use that location instead.

Manually merge reviewed settings from `daemon/shared.json` into the existing config. Keep host-specific values and authentication local. Do not replace the live file with the starter template, symlink it to this file, or commit the full `~/.paseo` directory.

After editing the live config:

```sh
paseo reload
```

If reload reports settings that require a restart, run `paseo daemon restart` when it is safe to interrupt the daemon. Paseo must be installed on the machine where these commands run.

There is no automatic merge or sync script in this starter. Git tracks reviewed common settings; applying them to each daemon is a separate step.

## Keep out of Git

Never commit tokens, API keys, passwords or password hashes, Hub relationship credentials, relay pairing links, session databases, or runtime state. Check staged changes with `git diff --cached` before committing. `.gitignore` is a guardrail, not a secret scanner.

Do not copy the entire daemon home between machines. Each daemon should keep its own identity and credentials. Authenticate agent providers separately on each host.

## Hub automation

Hub configuration is independent of daemon-local `config.json`. A trigger targets a daemon by slug and uses an absolute working directory on that machine; Hub does not clone the repository for you.

The live Hub `chat-trigger` is mirrored in `.paseo/triggers/chat-trigger.yml`. Hub itself was not changed, and no deployment or GitHub auto-sync is configured.

## References

- [Daemon configuration](https://paseo.sh/docs/configuration)
- [Hub configuration](https://paseo.sh/docs/hub/configuration)
- [Daemons in Hub](https://paseo.sh/docs/hub/daemons)
