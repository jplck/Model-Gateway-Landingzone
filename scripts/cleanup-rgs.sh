#!/usr/bin/env bash
# --------------------------------------------------------------------------
# Delete all resource groups containing 'hub' or 'spoke' in the name.
# Prompts for confirmation before deleting.
# --------------------------------------------------------------------------
set -euo pipefail

echo "Searching for resource groups with 'hub' or 'spoke' in the name..."
echo ""

# Skip managed resource groups (ME_*) — they're deleted automatically when their parent is deleted
RGS=$(az group list --query "[?contains(name,'hub') || contains(name,'spoke')].name" -o tsv | grep -v '^ME_' || true)

if [[ -z "$RGS" ]]; then
  echo "No matching resource groups found."
  exit 0
fi

echo "The following resource groups will be DELETED:"
echo ""
echo "$RGS" | while read -r rg; do echo "  - $rg"; done
echo ""
read -rp "Are you sure? Type 'yes' to confirm: " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "$RGS" | while read -r rg; do
  echo "Deleting $rg..."
  az group delete --name "$rg" --yes --no-wait
done

echo ""
echo "Deletion initiated (--no-wait). Monitor with: az group list -o table"
