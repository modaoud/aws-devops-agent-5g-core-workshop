#!/bin/bash
# =============================================================================
# Scenario 3 (5G): "The deployment that broke the AMF"
#
# Simulates: A CI/CD pipeline (or operator) pushes a non-existent image tag
# to the AMF deployment. Pods enter ImagePullBackOff — complete UE
# registration outage.
#
# Failure chain: Bad image tag → ImagePullBackOff → zero available replicas →
# all subscriber registrations fail → NOC alarm fires.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAMESPACE="demo-5g"
BAD_IMAGE="public.ecr.aws/aws-containers/5g-amf:v2.1.0-rc3"  # Does not exist

case "${1:-inject}" in
  inject)
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  5G SCENARIO 3: Bad AMF Image Deployment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Pushing bad image to AMF deployment..."
    echo "  Image: ${BAD_IMAGE}"
    echo ""

    kubectl set image deployment/amf -n ${NAMESPACE} amf="${BAD_IMAGE}"

    echo "  ✗ AMF image changed to non-existent tag"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ✅ FAILURE INJECTED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  📟 EXPECTED ALARM (check within 2-3 minutes):"
    echo "     • 5G-Core-AMF-Replicas-Unavailable  (unavailable replicas detected)"
    echo ""
    echo "  🔍 OBSERVE (once alarm fires):"
    echo "     kubectl get pods -n ${NAMESPACE} -l app=amf"
    echo "     kubectl describe pod -l app=amf -n ${NAMESPACE} | grep -A5 Events"
    echo ""
    echo "  🤖 DEVOPS AGENT PROMPT:"
    echo "     \"The AMF deployment in demo-5g namespace is failing. All new pods"
    echo "      are in ImagePullBackOff. Subscriber registrations are completely"
    echo "      down. Investigate what changed.\""
    echo ""
    echo "  🔄 RESTORE: $0 restore"
    echo ""
    ;;

  restore)
    echo "Rolling back AMF deployment..."

    kubectl rollout undo deployment/amf -n ${NAMESPACE}
    echo "  ✓ Rollback initiated"

    kubectl rollout status deployment/amf -n ${NAMESPACE} --timeout=120s
    echo ""
    echo "  ✅ AMF restored. UE registrations will resume."
    echo "     Alarm will return to OK within 1-2 minutes."
    ;;

  *)
    echo "Usage: $0 [inject|restore]"
    exit 1
    ;;
esac
