# paseo-config

Personal Paseo setup: one self-hosted Hub, a home daemon, and runner containers.

- [`config/`](config/): daemon settings, per-host overrides, Hub triggers, and `apply.sh` for one-command setup on a machine.
- [`plugins/`](plugins/): Paseo plugins installed on the daemons.
- [`daemon-setup/`](daemon-setup/): the runner image: Paseo daemon, agent CLIs, and MCP servers baked in, with secrets injected at runtime.

New machine:

```sh
curl -fsSL https://raw.githubusercontent.com/hampfh/paseo-config/main/config/apply.sh | bash
```
