# Local verification - 2026-06-09

## Commands
- `bash -n scripts/*.sh test/*.sh`: PASS
- `scripts/vpnkit-test-lab-setup.sh --endpoint 127.0.0.1 --port 21194`: PASS; generated ignored lab artifacts under `secrets/vpnkit-labs/steamdeck-host/` and printed only paths/metadata.
- `VPNKIT_TEST_SSH_TARGET= VPNKIT_TEST_ENDPOINT= test/containers-test.sh --scenario steamdeck-host --action test`: PASS for expected behavior (command exits 1 with explicit `FAIL lifecycle:prereq-endpoint`; no generated secret contents printed).
- `python3 -m py_compile scripts/*.py test/*.py`: PASS
- `python3 scripts/vpnkit-manifest-validate.py --manifest config/vpnkit-manifest.example.yaml --server steamdeck --client host-machine --profile-intent test`: NOT RUN/PASS blocked locally by missing public Python dependency `jsonschema`.
- `python3 test/sing-box-smart-routing-proof.py`: PASS
- `go test ./...`: PASS
- `go vet ./...`: PASS
- `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: PASS

## Artifact safety
- Generated `secrets/vpnkit-labs/steamdeck-host/`, `generated/`, and logs were removed after local checks.
- `git status --ignored` showed `secrets/` ignored before removal; no generated `.ovpn`, PEM/key/cert, rendered private config, or log artifacts are staged.
