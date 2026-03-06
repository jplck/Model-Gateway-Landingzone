#!/usr/bin/env python3
"""
Create an Entra Agent Identity Blueprint and link it to a Managed Identity.

Uses the Entra Agent ID endpoints (Graph beta) to create a proper
AgentIdentityBlueprint, link a Managed Identity via FIC, and create
the Blueprint Principal.

Prerequisites:
  - M365 Copilot license with Frontier program enabled
  - Agent ID Developer or Agent ID Administrator role
  - pip install azure-identity requests

Usage:
  python scripts/create_agent_blueprint.py

Environment variables (or prompted interactively):
  AZURE_TENANT_ID          - Your Entra tenant ID
  SPONSOR_USER_ID          - Object ID of the sponsoring user
  MI_PRINCIPAL_ID          - (Optional) Managed Identity principal ID for FIC
  BLUEPRINT_DISPLAY_NAME   - (Optional) Display name for the blueprint
"""

import json
import os
import sys

import requests
from azure.identity import InteractiveBrowserCredential

GRAPH_BETA = "https://graph.microsoft.com/beta"

REQUIRED_SCOPES = [
    "AgentIdentityBlueprint.Create",
    "AgentIdentityBlueprint.AddRemoveCreds.All",
    "AgentIdentityBlueprint.ReadWrite.All",
    "AgentIdentityBlueprintPrincipal.Create",
    "User.Read",
]


def get_env_or_prompt(var: str, prompt: str, required: bool = True) -> str:
    value = os.environ.get(var, "").strip()
    if not value:
        value = input(f"{prompt}: ").strip()
    if required and not value:
        print(f"Error: {var} is required.")
        sys.exit(1)
    return value


def graph_request(method: str, url: str, headers: dict, json_body: dict = None):
    resp = requests.request(method, url, headers=headers, json=json_body)
    if resp.status_code not in (200, 201, 204):
        print(f"   Error: {resp.status_code}")
        print(f"   {resp.text}")
        sys.exit(1)
    return resp


def main():
    print("=== Entra Agent Identity Blueprint Setup ===\n")

    tenant_id = get_env_or_prompt("AZURE_TENANT_ID", "Tenant ID")
    sponsor_user_id = get_env_or_prompt("SPONSOR_USER_ID", "Sponsor user object ID")
    mi_principal_id = get_env_or_prompt(
        "MI_PRINCIPAL_ID",
        "Managed Identity principal ID (leave blank to skip)",
        required=False,
    )
    blueprint_name = get_env_or_prompt(
        "BLUEPRINT_DISPLAY_NAME",
        "Blueprint display name (default: AI Gateway Agent Blueprint)",
        required=False,
    )
    if not blueprint_name:
        blueprint_name = "AI Gateway Agent Blueprint"

    # --- Authenticate interactively with Agent ID scopes ---
    print(f"\nAuthenticating to tenant {tenant_id}...")
    credential = InteractiveBrowserCredential(tenant_id=tenant_id)
    token = credential.get_token(*REQUIRED_SCOPES).token

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "OData-Version": "4.0",
    }

    # --- Step 1: Create the Agent Identity Blueprint ---
    print(f"\n1. Creating blueprint '{blueprint_name}'...")
    resp = graph_request(
        "POST",
        f"{GRAPH_BETA}/applications/",
        headers,
        {
            "@odata.type": "Microsoft.Graph.AgentIdentityBlueprint",
            "displayName": blueprint_name,
            "sponsors@odata.bind": [
                f"https://graph.microsoft.com/v1.0/users/{sponsor_user_id}"
            ],
            "owners@odata.bind": [
                f"https://graph.microsoft.com/v1.0/users/{sponsor_user_id}"
            ],
        },
    )
    blueprint = resp.json()
    blueprint_id = blueprint["id"]
    blueprint_app_id = blueprint["appId"]
    print(f"   Blueprint created.")
    print(f"   Object ID: {blueprint_id}")
    print(f"   App ID:    {blueprint_app_id}")

    # --- Step 2: Add FIC for Managed Identity (optional) ---
    if mi_principal_id:
        print(f"\n2. Linking Managed Identity ({mi_principal_id}) via FIC...")
        resp = graph_request(
            "POST",
            f"{GRAPH_BETA}/applications/{blueprint_id}/federatedIdentityCredentials",
            headers,
            {
                "name": "container-app-mi",
                "issuer": f"https://login.microsoftonline.com/{tenant_id}/v2.0",
                "subject": mi_principal_id,
                "audiences": ["api://AzureADTokenExchange"],
            },
        )
        print("   FIC linked successfully.")
    else:
        print("\n2. Skipping FIC (no MI_PRINCIPAL_ID provided).")

    # --- Step 3: Create Blueprint Principal ---
    print("\n3. Creating blueprint principal...")
    resp = graph_request(
        "POST",
        f"{GRAPH_BETA}/serviceprincipals/graph.agentIdentityBlueprintPrincipal",
        headers,
        {"appId": blueprint_app_id},
    )
    principal = resp.json()
    print(f"   Principal created: {principal.get('id')}")

    # --- Step 4: Create Agent Identity ---
    print("\n4. Creating agent identity...")
    resp = graph_request(
        "POST",
        f"{GRAPH_BETA}/serviceprincipals/Microsoft.Graph.AgentIdentity",
        headers,
        {
            "blueprintId": blueprint_app_id,
            "displayName": f"{blueprint_name} - Agent",
        },
    )
    agent_identity = resp.json()
    agent_identity_id = agent_identity.get("id")
    agent_identity_app_id = agent_identity.get("appId")
    print(f"   Agent Identity created.")
    print(f"   ID:     {agent_identity_id}")
    print(f"   App ID: {agent_identity_app_id}")

    # --- Summary ---
    print("\n" + "=" * 60)
    print("Blueprint setup complete!\n")
    print("Set these on your Container App (or in azd env):")
    print(f"  BLUEPRINT_APP_ID={blueprint_app_id}")
    print(f"  AGENT_IDENTITY_APP_ID={agent_identity_app_id}")
    print()
    print("To exchange tokens (T1/T2 flow), your MI uses FIC to")
    print("get a T1 assertion with fmi_path=<agent_identity_app_id>,")
    print("then exchanges it for a T2 access token.")
    print("=" * 60)

    output = {
        "blueprintObjectId": blueprint_id,
        "blueprintAppId": blueprint_app_id,
        "blueprintPrincipalId": principal.get("id"),
        "agentIdentityId": agent_identity_id,
        "agentIdentityAppId": agent_identity_app_id,
        "tenantId": tenant_id,
        "sponsorUserId": sponsor_user_id,
        "miPrincipalId": mi_principal_id or None,
    }
    output_path = os.path.join(os.path.dirname(__file__), "agent-blueprint.json")
    with open(output_path, "w") as f:
        json.dump(output, f, indent=2)
    print(f"\nSaved details to {output_path}")


if __name__ == "__main__":
    main()
