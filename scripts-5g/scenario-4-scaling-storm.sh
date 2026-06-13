#!/bin/bash
# =============================================================================
# Scenario 4 (5G): "The scaling storm during busy hour"
#
# Simulates: An engineer misconfigures the AMF HPA — CPU target too low (15%),
# stabilization window removed, aggressive scale policies. Under load, the HPA
# thrashes between scale-up and scale-down, causing pod churn and intermittent
# registration failures.
#
# Failure chain: Low HPA target → rapid scale-up → metrics drop (new pods
# cold) → immediate scale-down → metrics spike again → repeat. Each cycle
# kills in-flight connections and hammers Redis with new connections.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAMESPACE="demo-5g"

case "${1:-inject}" in
  inject)
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  5G SCENARIO 4: AMF HPA Scaling Storm"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo "  Misconfiguring AMF HPA..."
    kubectl patch hpa amf-hpa -n ${NAMESPACE} --type=merge -p '{
      "spec": {
        "metrics": [{"type": "Resource", "resource": {"name": "cpu", "target": {"type": "Utilization", "averageUtilization": 15}}}],
        "behavior": {
          "scaleDown": {"stabilizationWindowSeconds": 0, "policies": [{"type": "Percent", "value": 50, "periodSeconds": 15}]},
          "scaleUp": {"stabilizationWindowSeconds": 0, "policies": [{"type": "Percent", "value": 100, "periodSeconds": 15}]}
        }
      }
    }'

    echo "  ✗ HPA target: 70% → 15% CPU"
    echo "  ✗ Stabilization window: 60s → 0s (both directions)"
    echo "  ✗ Scale policies: aggressive (50% down / 100% up every 15s)"
    echo ""

    echo "  Starting busy hour traffic..."
    kubectl patch deployment ue-simulator -n ${NAMESPACE} \
      -p '{"spec":{"replicas":3}}' 2>/dev/null || true
    kubectl set env deployment/ue-simulator -n ${NAMESPACE} \
      REQUESTS_PER_SECOND=15 2>/dev/null || true

    echo "  ✓ UE simulator: 3 replicas @ 15 RPS each (45 registrations/sec)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ✅ FAILURE INJECTED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  📟 EXPECTED ALARMS (watch for 2-3 minutes):"
    echo "     ⚠️  Unlike other scenarios, alarms will OSCILLATE (fire → recover → fire)"
    echo "     This IS the scenario — the system looks sick/healthy/sick/healthy."
    echo ""
    echo "     • 5G-Core-AMF-HPA-Scaling-Storm     (fires on scale-up, clears on scale-down)"
    echo "     • 5G-Core-AMF-Replicas-Unavailable   (brief flickers during pod transitions)"
    echo "     • 5G-Core-NF-Not-Ready               (brief flickers during scale-down)"
    echo ""
    echo "  🔍 OBSERVE (once alarm fires):"
    echo "     kubectl get hpa -n ${NAMESPACE} -w"
    echo "     kubectl get pods -n ${NAMESPACE} -l app=amf -w"
    echo ""
    echo "  🤖 DEVOPS AGENT PROMPT:"
    echo "     \"The AMF HPA in demo-5g is rapidly scaling pods up and down."
    echo "      We're seeing intermittent subscriber registration failures"
    echo "      during busy hour. Investigate the scaling behavior.\""
    echo ""
    echo "  💡 WHAT TO LOOK FOR:"
    echo "     • HPA oscillation pattern (2→9→2→7→...)"
    echo "     • CPU target too low (15%) causing over-reaction"
    echo "     • Stabilization window at 0s allowing instant scale-down"
    echo "     • Redis connection churn from rapid pod turnover"
    echo ""
    echo "  🔄 RESTORE: $0 restore"
    echo ""
    ;;

  restore)
    echo "Restoring AMF HPA configuration..."

    kubectl patch hpa amf-hpa -n ${NAMESPACE} --type=merge -p '{
      "spec": {
        "metrics": [{"type": "Resource", "resource": {"name": "cpu", "target": {"type": "Utilization", "averageUtilization": 70}}}],
        "behavior": {
          "scaleDown": {"stabilizationWindowSeconds": 60},
          "scaleUp": {"stabilizationWindowSeconds": 0, "policies": [{"type": "Percent", "value": 100, "periodSeconds": 15}]}
        }
      }
    }'

    kubectl patch deployment ue-simulator -n ${NAMESPACE} \
      -p '{"spec":{"replicas":0}}' 2>/dev/null || true

    echo "  ✓ HPA target restored to 70%"
    echo "  ✓ Stabilization window restored to 60s (scale-down)"
    echo "  ✓ UE simulator stopped"
    echo ""
    echo "  ✅ AMF scaling will stabilize within 2-3 minutes."
    echo "     Alarm will return to OK once replica count drops below 6."
    ;;

  *)
    echo "Usage: $0 [inject|restore]"
    exit 1
    ;;
esac
