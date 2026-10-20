# Bootstrap

What a tenant needs before the first deployment, and before the pipeline can sign in. A script,
not a template: it creates Entra objects and role assignments that no stack should own. Run it
once per tenant; running it again changes only what's missing.

```bash
solutions/00-init-000-bootstrap/bootstrap.sh --dry-run --repo <owner>/<repo> --github   # read first
solutions/00-init-000-bootstrap/bootstrap.sh --repo <owner>/<repo> --github
```

Run it from the repo root as a Global Administrator with elevated access, signed in with
`az login` (and `gh auth login` for `--github`).

| Step | What | Why here |
|---|---|---|
| Resource providers | `Microsoft.AAD`, `Microsoft.ContainerRegistry`, `Microsoft.Network`, `Microsoft.OperationalInsights`, `Microsoft.SecurityInsights`, `Microsoft.Storage` in every subscription of `platform.json` | A deployment fails on an unregistered provider, and the deployer shouldn't need the right to register them |
| Entra Domain Services prerequisites | The Domain Controller Services service principal and the `AAD DC Administrators` group | The managed domain needs both before it deploys; neither is an Azure resource a stack could own |
| Deployer | App registration, federated credentials for `main`, `dev`, `prod`; Owner at the tenant root group | Creates management groups and moves subscriptions, which needs role assignment rights on them |
| Previewer | App registration, federated credentials for `dev-preview`, `prod-preview`; Reader at the tenant root group | What-if and stack what-if, nothing else |
| `platform.json` | Writes `tenantId` and both principal IDs | The registry grants AcrPush and AcrPull to them |
| GitHub, with `--github` | Creates the four environments, sets `AZURE_TENANT_ID` and `AZURE_CLIENT_ID` | The workflows read them; no secrets |

Owner at the tenant root group is broad, and it's what the management group stacks at the tenant
root group need. Keep the deployer's federated credentials to `main` and the approved environments.

Not a component: no version, no stack, never published. `scripts/tests/bootstrap.test.sh` runs
it against a fake `az` and `gh`.
