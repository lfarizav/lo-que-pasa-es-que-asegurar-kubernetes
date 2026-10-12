#!/usr/bin/env bash
# lab-part-05 step 3 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/cks-lab/p05"
K="kubectl --kubeconfig $D/kubeconfig --context kind-cks-p05"
NS=la-bodega
TAG=2026-08
REG=127.0.0.1:5065
ACEPTA='application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
export TRIVY_CACHE_DIR="$D/trivy-cache"
test -x "$D/trivy" || exit 1
test -f "$D/03-respuesta.txt" || exit 1
CVE=$(grep -m1 '^CVE_CRITICO=' "$D/03-respuesta.txt" | cut -d= -f2-)
RECH=$(grep -m1 '^PROVEEDOR_RECHAZADO=' "$D/03-respuesta.txt" | cut -d= -f2-)
APRO=$(grep -m1 '^PROVEEDOR_APROBADO=' "$D/03-respuesta.txt" | cut -d= -f2-)
echo "$CVE" | grep -Eq '^CVE-[0-9]{4}-[0-9]{4,}$' || exit 1
SUCIO=""
LIMPIO=""
for REPO in tienda/proveedor-a tienda/proveedor-b; do
  rm -f "$D/.chequeo-scan.json"
  "$D/trivy" image --scanners vuln --severity CRITICAL --format json --quiet \
    --skip-db-update --skip-java-db-update -o "$D/.chequeo-scan.json" "$REG/$REPO:$TAG" >/dev/null 2>&1 || exit 1
  N=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "$D/.chequeo-scan.json" 2>/dev/null)
  echo "$N" | grep -Eq '^[0-9]+$' || { rm -f "$D/.chequeo-scan.json"; exit 1; }
  if [ "$N" -gt 0 ]; then
    SUCIO="$REPO"
    jq -e --arg c "$CVE" '[.Results[]?.Vulnerabilities[]? | select(.VulnerabilityID == $c and .Severity == "CRITICAL")] | length > 0' "$D/.chequeo-scan.json" >/dev/null || { rm -f "$D/.chequeo-scan.json"; exit 1; }
  else
    LIMPIO="$REPO"
    jq -e --arg c "$CVE" '[.Results[]?.Vulnerabilities[]? | select(.VulnerabilityID == $c)] | length == 0' "$D/.chequeo-scan.json" >/dev/null || { rm -f "$D/.chequeo-scan.json"; exit 1; }
  fi
  rm -f "$D/.chequeo-scan.json"
done
test -n "$SUCIO" || exit 1
test -n "$LIMPIO" || exit 1
test "$RECH" = "$SUCIO" || exit 1
test "$APRO" = "$LIMPIO" || exit 1
DIG_LIMPIO=$(curl -sI --max-time 10 -H "Accept: $ACEPTA" "http://$REG/v2/$LIMPIO/manifests/$TAG" 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}')
DIG_SUCIO=$(curl -sI --max-time 10 -H "Accept: $ACEPTA" "http://$REG/v2/$SUCIO/manifests/$TAG" 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}')
echo "$DIG_LIMPIO" | grep -Eq '^sha256:[0-9a-f]{64}$' || exit 1
echo "$DIG_SUCIO" | grep -Eq '^sha256:[0-9a-f]{64}$' || exit 1
DES=$($K -n $NS get deploy el-proveedor -o json 2>/dev/null)
test -n "$DES" || exit 1
test "$(echo "$DES" | jq -r '.status.readyReplicas // 0')" -ge 2 || exit 1
PODS=$($K -n $NS get pods -o json 2>/dev/null | jq -c '[.items[] | select(.metadata.deletionTimestamp == null)]')
VIVOS=$(echo "$PODS" | jq -c '[.[] | select(.status.phase == "Running") | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))]')
test "$(echo "$VIVOS" | jq 'length')" -ge 2 || exit 1
HUELLAS=$(echo "$VIVOS" | jq -r '[.[].status.containerStatuses[]?.imageID] | unique | .[]')
test -n "$HUELLAS" || exit 1
for H in $HUELLAS; do
  case "$H" in *"@$DIG_LIMPIO") ;; *) exit 1 ;; esac
done
echo "$PODS" | jq -e --arg s "$SUCIO" '[.[] | (.spec.containers[], (.spec.initContainers[]? // empty)) | .image] | any(index($s) != null) | not' >/dev/null || exit 1
echo "$PODS" | jq -e --arg d "$DIG_SUCIO" '[.[] | .status.containerStatuses[]?.imageID] | any(index($d) != null) | not' >/dev/null || exit 1
echo ok
