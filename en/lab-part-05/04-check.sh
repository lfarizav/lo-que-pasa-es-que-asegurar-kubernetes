#!/usr/bin/env bash
# lab-part-05 step 4 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/cks-lab/p05"
K="kubectl --kubeconfig $D/kubeconfig --context kind-cks-p05"
NS=el-deposito
TAG=2026-08
REG=127.0.0.1:5065
CREG=cks-p05-registry:5000
ACEPTA='application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
export TRIVY_CACHE_DIR="$D/trivy-cache"
test -f "$D/04-respuesta.txt" || exit 1
test -x "$D/cosign" || exit 1
test -x "$D/trivy" || exit 1
test -f "$D/despacho.pub" || exit 1
POL=$(grep -m1 '^POLITICA_VERIFY=' "$D/04-respuesta.txt" | cut -d= -f2-)
DIG=$(grep -m1 '^DIGEST_FIRMADO=' "$D/04-respuesta.txt" | cut -d= -f2-)
test -n "$POL" || exit 1
echo "$DIG" | grep -Eq '^sha256:[0-9a-f]{64}$' || exit 1
SUCIO=""
LIMPIO=""
for REPO in tienda/proveedor-a tienda/proveedor-b; do
  rm -f "$D/.sello-scan.json"
  "$D/trivy" image --scanners vuln --severity CRITICAL --format json --quiet \
    --skip-db-update --skip-java-db-update -o "$D/.sello-scan.json" "$REG/$REPO:$TAG" >/dev/null 2>&1 || exit 1
  N=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "$D/.sello-scan.json" 2>/dev/null)
  rm -f "$D/.sello-scan.json"
  echo "$N" | grep -Eq '^[0-9]+$' || exit 1
  if [ "$N" -gt 0 ]; then SUCIO="$REPO"; else LIMPIO="$REPO"; fi
done
test -n "$SUCIO" || exit 1
test -n "$LIMPIO" || exit 1
DIG_LIMPIO=$(curl -sI --max-time 10 -H "Accept: $ACEPTA" "http://$REG/v2/$LIMPIO/manifests/$TAG" 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}')
DIG_SUCIO=$(curl -sI --max-time 10 -H "Accept: $ACEPTA" "http://$REG/v2/$SUCIO/manifests/$TAG" 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}')
echo "$DIG_LIMPIO" | grep -Eq '^sha256:[0-9a-f]{64}$' || exit 1
echo "$DIG_SUCIO" | grep -Eq '^sha256:[0-9a-f]{64}$' || exit 1
test "$DIG" = "$DIG_LIMPIO" || exit 1
"$D/cosign" verify --key "$D/despacho.pub" --insecure-ignore-tlog --allow-insecure-registry "$REG/$LIMPIO@$DIG_LIMPIO" >/dev/null 2>&1 || exit 1
if "$D/cosign" verify --key "$D/despacho.pub" --insecure-ignore-tlog --allow-insecure-registry "$REG/$SUCIO@$DIG_SUCIO" >/dev/null 2>&1; then exit 1; fi
$K get clusterpolicy "$POL" >/dev/null 2>&1 || exit 1
$K get clusterpolicy "$POL" -o json 2>/dev/null | jq -e '[.spec.rules[]?.verifyImages[]? | select((.failureAction // "Enforce") == "Enforce")] | length > 0' >/dev/null || exit 1
APROBADO=$($K -n $NS get pod el-aprobado -o json 2>/dev/null)
test -n "$APROBADO" || exit 1
test "$(echo "$APROBADO" | jq -r '.status.phase')" = "Running" || exit 1
case "$(echo "$APROBADO" | jq -r '.spec.containers[0].image')" in *"@$DIG_LIMPIO") ;; *) exit 1 ;; esac
$K -n $NS delete pod chequeo-sello-ok chequeo-sello-malo --ignore-not-found --wait=true >/dev/null 2>&1
$K apply -f - >/dev/null 2>&1 <<YAML || exit 1
apiVersion: v1
kind: Pod
metadata:
  name: chequeo-sello-ok
  namespace: $NS
spec:
  containers:
  - name: app
    image: $CREG/$LIMPIO:$TAG
    resources:
      limits:
        cpu: 100m
        memory: 64Mi
YAML
OK=$($K -n $NS get pod chequeo-sello-ok -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)
$K -n $NS delete pod chequeo-sello-ok --ignore-not-found --wait=false >/dev/null 2>&1
case "$OK" in *"@$DIG_LIMPIO") ;; *) exit 1 ;; esac
if $K apply -f - >/dev/null 2>&1 <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: chequeo-sello-malo
  namespace: $NS
spec:
  containers:
  - name: app
    image: $CREG/$SUCIO:$TAG
    resources:
      limits:
        cpu: 100m
        memory: 64Mi
YAML
then
  $K -n $NS delete pod chequeo-sello-malo --ignore-not-found --wait=false >/dev/null 2>&1
  exit 1
fi
echo ok
