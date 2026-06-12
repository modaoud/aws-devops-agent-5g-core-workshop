#!/bin/bash
# =============================================================================
# Scenario 1 (5G): "Who changed the Security Group?"
#
# Simulates: A team member modifies the Redis Security Group, blocking port
# 6379 from EKS pod subnets. NRF loses its Redis backend, causing a cascade
# failure across the entire 5G core.
#
# Failure chain: SG revoked → NRF can't reach Redis → readiness probe fails →
# NRF returns 503 on all discovery requests → AMF/SMF can't discover peers →
# PDU sessions fail network-wide.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

case "${1:-inject}" in
  inject)
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  5G SCENARIO 1: Security Group Change — Redis Connectivity Severed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    SG_ID=$(terraform -chdir="${SCRIPT_DIR}/../terraform" output -raw redis_security_group_id)
    CIDRS=$(terraform -chdir="${SCRIPT_DIR}/../terraform" output -json vpc_private_subnet_cidrs | jq -r '.[]')

    echo "  Security Group: ${SG_ID}"
    echo "  Action: Revoking inbound port 6379 from pod CIDRs"
    echo ""

    IP_RANGES=$(echo "$CIDRS" | jq -R '{"CidrIp": .}' | jq -s '.')

    aws ec2 revoke-security-group-ingress \
      --group-id "$SG_ID" \
      --ip-permissions "[{\"IpProtocol\":\"tcp\",\"FromPort\":6379,\"ToPort\":6379,\"IpRanges\":${IP_RANGES}}]" \
      --region us-east-1 > /dev/null

    for cidr in $CIDRS; do
      echo "  ✗ Revoked: ${cidr} → port 6379"
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ✅ FAILURE INJECTED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  📟 EXPECTED ALARMS (check within 1-2 minutes):"
    echo "     • 5G-Core-NRF-Redis-Disconnected  (NewConnections drops to 0)"
    echo "     May also trigger:"
    echo "     • 5G-Core-NF-Not-Ready            (NRF service endpoints drop)"
    echo "     • 5G-Core-AMF-Replicas-Unavailable (AMF cascade — loses NRF health)"
    echo ""
    echo "  🔍 OBSERVE (once alarms fire):"
    echo "     kubectl logs -l nf-type=nrf -n demo-5g --tail=5"
    echo "     kubectl logs -l nf-type=amf -n demo-5g --tail=5"
    echo ""
    echo "  🤖 DEVOPS AGENT PROMPT:"
    echo "     \"The 5G core NFs in demo-5g namespace are failing to establish"
    echo "      PDU sessions. AMF logs show NRF discovery failures starting"
    echo "      about 1 minute ago. Investigate.\""
    echo ""
    echo "  🔄 RESTORE: $0 restore"
    echo ""
    ;;

  restore)
    echo "Restoring Redis SG rules..."

    SG_ID=$(terraform -chdir="${SCRIPT_DIR}/../terraform" output -raw redis_security_group_id)
    CIDRS=$(terraform -chdir="${SCRIPT_DIR}/../terraform" output -json vpc_private_subnet_cidrs | jq -r '.[]')

    IP_RANGES=$(echo "$CIDRS" | jq -R '{"CidrIp": ., "Description": "Redis from EKS pods"}' | jq -s '.')

    aws ec2 authorize-security-group-ingress \
      --group-id "$SG_ID" \
      --ip-permissions "[{\"IpProtocol\":\"tcp\",\"FromPort\":6379,\"ToPort\":6379,\"IpRanges\":${IP_RANGES}}]" \
      --region us-east-1 > /dev/null

    for cidr in $CIDRS; do
      echo "  ✓ Restored: ${cidr} → port 6379"
    done

    echo ""
    echo "  ✅ Redis connectivity restored. NRF will re-register NFs within 30s."
    echo "     Alarms will return to OK within 1-2 minutes."
    ;;

  *)
    echo "Usage: $0 [inject|restore]"
    exit 1
    ;;
esac
