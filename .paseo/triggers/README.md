# Hub triggers

Place reviewed trigger YAML files directly in this directory, one trigger per `.yml` file.

`chat-trigger.yml` mirrors the live Hub `chat-trigger` as of 2026-11-05 (copied from the Hub YAML editor). Deploying it unchanged is a no-op.

From this repository, `paseo hub init` can generate a starter trigger. Review its daemon slug, absolute working directory, agent settings, and allowed users before deploying with `paseo hub deploy`.

Treat deployment as a separate action: it changes Hub automation configuration.

Reference: https://paseo.sh/docs/hub/configuration
