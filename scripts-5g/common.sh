#!/bin/bash
# Common helpers for demo scripts

# Verify prerequisites
command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI required"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl required"; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "ERROR: terraform required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required"; exit 1; }

# Verify kubectl context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || true)
if [[ -z "$CURRENT_CONTEXT" ]]; then
  echo "ERROR: No kubectl context set. Run:"
  echo "  aws eks update-kubeconfig --name devops-agent-demo --region us-east-1"
  exit 1
fi
