# TODO: Switch to Ad-Hoc Agent Identity Provisioning

Move from one static, pre-provisioned Agent Identity → per-session Agent Identities minted by the Blueprint at runtime.

Pattern: **Container App MI → FIC → Blueprint Principal → `POST /agentIdentities` → ephemeral Agent Identity**

---

## 1. Setup script — `scripts/setup_agent_identity.sh`

- [ ] Keep step 1: create/find **Blueprint** (`agentIdentityBlueprint`)
- [ ] Keep step 2: create/find **Blueprint Service Principal** (`agentIdentityBlueprintPrincipal`)
- [ ] Keep FIC creation trusting the Container App managed identity
- [ ] **Remove** step 3 (static Agent Identity creation) and the temporary client-secret dance
- [ ] Add `inheritablePermissions` on the Blueprint so child agents auto-inherit resource scopes (Graph/MS resources)
- [ ] Add `requiredResourceAccess` upfront (Storage, APIM scope, Foundry) on the Blueprint
- [ ] Create a security group (e.g. `sg-agents-<env>`) and store its object id in azd env
- [ ] Grant the **Blueprint SP** these Graph application permissions + admin consent:
  - [ ] `AgentIdentity.ReadWrite.All`
  - [ ] `GroupMember.ReadWrite.All` (only if going the group-RBAC route)
- [ ] Stop emitting `AGENT_IDENTITY_APP_ID` to azd env

---

## 2. Bicep — `infra/spoke.bicep` and modules

- [ ] Remove `AGENT_IDENTITY_APP_ID` parameter and Container App env var
- [ ] Keep `blueprintAppId` parameter
- [ ] Add `agentsGroupObjectId` parameter
- [ ] Move RBAC role assignments (Storage Blob Data Contributor, Foundry roles, APIM consumer, …) from the Agent Identity → the **security group**
- [ ] Confirm Container App MI still has FIC subject claim wiring intact

---

## 3. RBAC strategy

Pick **group-based RBAC** (recommended) — required because per-agent role assignments would need elevated runtime privileges and add latency:

- [ ] All Azure ARM RBAC role assignments target the group
- [ ] Runtime adds each new Agent Identity to the group via Graph
- [ ] Document fallback: `inheritablePermissions` only covers Microsoft Graph / MS resources, not ARM RBAC

---

## 4. Runtime — `apps/chat-agent/`

- [ ] New module `agent_identity_manager.py`:
  - [ ] `acquire_blueprint_graph_token()` — call sidecar to get a Graph token issued to the Blueprint (`scope=https://graph.microsoft.com/.default`)
  - [ ] `create_agent_identity(session_id, user_hint) -> appId` — `POST https://graph.microsoft.com/beta/agentIdentities` with `agentIdentityBlueprintId = BLUEPRINT_APP_ID`
  - [ ] `add_to_group(agent_object_id)` — `POST /groups/{id}/members/$ref`
  - [ ] `delete_agent_identity(agent_object_id)` — on session end
  - [ ] In-memory cache keyed by session id (TTL + max size)
- [ ] Update `inference.py` and `main.py`:
  - [ ] Replace static `AGENT_IDENTITY_APP_ID` with `session_agent_app_id`
  - [ ] Pass it as `params["AgentIdentity"]` on every sidecar `/AuthorizationHeaderUnauthenticated/*` call
- [ ] Update `config.py`: drop `AGENT_IDENTITY_APP_ID`, add `AGENTS_GROUP_OBJECT_ID`
- [ ] Update `.env.sample` accordingly

---

## 5. Lifecycle & hygiene

- [ ] Delete agent identity on session end (FastAPI shutdown / explicit logout)
- [ ] Background reconciliation job: list agents where `agentIdentityBlueprintId eq '<BLUEPRINT_APP_ID>'` and delete orphans older than N hours
- [ ] Watch tenant agent-identity quota — add metrics/alerts
- [ ] Log `agent_identity_id` in every span/trace (this is the main audit benefit)

---

## 6. Sidecar

- [ ] No config change needed — the M365 auth sidecar already accepts `AgentIdentity` as a per-request query parameter
- [ ] Verify FIC on Blueprint remains untouched

---

## 7. Documentation

- [ ] Update `architecture.md` token-flow diagram: replace single Agent Identity with "ephemeral Agent Identity (per session)"
- [ ] Update `deepdive.md` Agent ID section
- [ ] Update `architecture.drawio` blueprint/agent-identity boxes

---

## 8. Validation

- [ ] Local: trigger two parallel chat sessions, confirm two distinct `agentIdentityBlueprintId`-linked agents created
- [ ] Confirm Storage / Foundry / APIM calls succeed via group inheritance
- [ ] Confirm cleanup deletes both on session end
- [ ] Run reconciliation job — confirm it deletes a manually-orphaned agent
- [ ] Audit log review: each Storage call traces to a unique agent identity

---

## References

- [agentIdentityBlueprint](https://learn.microsoft.com/en-us/graph/api/resources/agentidentityblueprint)
- [agentIdentityBlueprintPrincipal](https://learn.microsoft.com/en-us/graph/api/resources/agentidentityblueprintprincipal)
- [agentIdentity](https://learn.microsoft.com/en-us/graph/api/resources/agentidentity)
