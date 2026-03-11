#!/usr/bin/env bash
# --------------------------------------------------------------------------
# preprovision hook — prompts for optional features before azd provision
# --------------------------------------------------------------------------
set -euo pipefail

eval "$(azd env get-values 2>/dev/null | tr -d '\r')" || true

# --- A365 Observability ---
CURRENT="${ENABLE_A365_OBSERVABILITY:-false}"
if [[ "$CURRENT" != "true" ]]; then
  echo ""
  read -r -p "Enable A365 observability telemetry? (requires Agent ID auth sidecar) [y/N] " answer
  case "${answer,,}" in
    y|yes)
      azd env set ENABLE_A365_OBSERVABILITY true
      echo "  ✓ A365 observability will be enabled"
      ;;
    *)
      echo "  Skipped (set ENABLE_A365_OBSERVABILITY=true to enable later)"
      ;;
  esac
fi
