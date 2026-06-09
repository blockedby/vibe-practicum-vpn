# Live Deck verification - 2026-06-09

Not run: `config/private-endpoints.local.env` is absent in this worktree, so no authorized private Deck SSH target/endpoint values were available. Remaining live acceptance requires sourcing that gitignored file and running:

```bash
test -r config/private-endpoints.local.env && set -a && . config/private-endpoints.local.env && set +a
test/containers-test.sh --scenario steamdeck-host --action cycle
```

The runner now fails explicit `steamdeck-host` missing endpoint prerequisites rather than counting them as green acceptance.
