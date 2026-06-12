#!/bin/bash
# =============================================================================
# Scenario 2 (5G): "Pods won't schedule during busy hour"
#
# Simulates: Peak traffic drives AMF HPA scale-up, but the ASG is already at
# max capacity. New AMF pods are stuck in Pending — subscriber registrations
# degrade as existing pods are overloaded.
#
# Failure chain: ASG max capped → AMF replicas requested > schedulable →
# FailedScheduling events → subscribers queue → registration timeouts.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

CLUSTER_NAME=$(terraform -chdir="${SCRIPT_DIR}/../terraform" output -raw cluster_name)
REGION="us-east-1"
NAMESPACE="demo-5g"

get_app_asg_name() {
  local NODEGROUP
  NODEGROUP=$(aws eks list-nodegroups \
    --cluster-name "$CLUSTER_NAME" \
    --query 'nodegroups[?starts_with(@, `app-`)] | [0]' \
    --output text \
    --region "${REGION}")

  if [[ -z "$NODEGROUP" || "$NODEGROUP" == "None" ]]; then
    echo "ERROR: Could not find app node group" >&2
    exit 1
  fi

  aws eks describe-nodegroup \
    --cluster-name "$CLUSTER_NAME" \
    --nodegroup-name "$NODEGROUP" \
    --query 'nodegroup.resources.autoScalingGroups[0].name' \
    --output text \
    --region "${REGION}"
}

case "${1:-inject}" in
  inject)
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  5G SCENARIO 2: ASG Ceiling During Busy Hour"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    APP_ASG=$(get_app_asg_name)
    echo "  App ASG: ${APP_ASG}"

    # Cap ASG at 2 nodes and scale down to 2 (simulate pre-existing capacity constraint)
    aws autoscaling update-auto-scaling-group \
      --auto-scaling-group-name "$APP_ASG" \
      --min-size 2 \
      --max-size 2 \
      --desired-capacity 2 \
      --region "${REGION}"
    echo "  ✗ ASG capped at max=2 (simulating cost-control policy)"

    # Wait for extra node to drain
    echo "  ⏳ Waiting for node scale-in (30s)..."
    sleep 30

    # Remove HPA so manual scaling simulates ops team response
    kubectl delete hpa amf-hpa -n ${NAMESPACE} 2>/dev/null || true
    echo "  ✗ AMF HPA removed (simulating manual capacity increase)"

    # Scale AMF beyond what 2 nodes can handle
    kubectl scale deployment amf -n ${NAMESPACE} --replicas=8
    echo "  ✗ AMF scaled to 8 replicas (simulating busy hour demand)"

    # Start UE simulator to show pressure
    kubectl patch deployment ue-simulator -n ${NAMESPACE} \
      -p '{"spec":{"replicas":2}}' 2>/dev/null || true
    echo "  ✓ UE simulator started (mass UE attach in progress)"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ✅ FAILURE INJECTED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  📟 EXPECTED ALARMS (check within 2-3 minutes):"
    echo "     • 5G-Core-AMF-Replicas-Unavailable  (pods can't schedule)"
    echo "     • 5G-Core-AMF-HPA-Scaling-Storm     (desired replicas > 6)"
    echo ""
    echo "  🔍 OBSERVE (once alarms fire):"
    echo "     kubectl get pods -n ${NAMESPACE} -l app=amf"
    echo "     kubectl describe pod <pending-amf-pod> -n ${NAMESPACE}"
    echo ""
    echo "  🤖 DEVOPS AGENT PROMPT:"
    echo "     \"AMF pods in demo-5g namespace are stuck in Pending state."
    echo "      We're seeing subscriber registration timeouts during peak"
    echo "      busy hour. Investigate why AMF cannot scale.\""
    echo ""
    echo "  🔄 RESTORE: $0 restore"
    echo ""
    ;;

  restore)
    echo "Restoring ASG and AMF scaling..."

    APP_ASG=$(get_app_asg_name)

    aws autoscaling update-auto-scaling-group \
      --auto-scaling-group-name "$APP_ASG" \
      --min-size 2 \
      --max-size 3 \
      --desired-capacity 2 \
      --region "${REGION}"
    echo "  ✓ ASG restored (min=2, max=3, desired=2)"

    kubectl scale deployment amf -n ${NAMESPACE} --replicas=2
    echo "  ✓ AMF scaled back to 2 replicas"

    kubectl patch deployment ue-simulator -n ${NAMESPACE} \
      -p '{"spec":{"replicas":0}}' 2>/dev/null || true
    echo "  ✓ UE simulator stopped"

    # Restore HPA from manifest
    kubectl apply -f "${SCRIPT_DIR}/../k8s-5g/amf.yaml" 2>/dev/null || true
    echo "  ✓ AMF HPA restored"

    echo ""
    echo "  ✅ Cluster will stabilize within 2-3 minutes."
    echo "     Alarms will return to OK once pods are rescheduled."
    ;;

  *)
    echo "Usage: $0 [inject|restore]"
    exit 1
    ;;
esac
