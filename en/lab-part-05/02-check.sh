#!/usr/bin/env bash
# lab-part-05 step 2 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/cks-lab/p05"
K="kubectl --kubeconfig $D/kubeconfig --context kind-cks-p05"
NS=la-vitrina
test -f "$D/02-respuesta.txt" || exit 1
ACEPTA='application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
REG=$(curl -sI --max-time 10 -H "Accept: $ACEPTA" http://127.0.0.1:5065/v2/tienda/pan/manifests/v1 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}')
echo "$REG" | grep -Eq '^sha256:[0-9a-f]{64}$' || exit 1
DES=$($K -n $NS get deploy la-vitrina -o json 2>/dev/null)
test -n "$DES" || exit 1
IMG=$(echo "$DES" | jq -r '.spec.template.spec.containers[0].image')
case "$IMG" in *"@$REG") ;; *) exit 1 ;; esac
test "$(echo "$DES" | jq -r '.spec.replicas')" = "2" || exit 1
LISTAS=$(echo "$DES" | jq -r '.status.readyReplicas // 0')
test "$LISTAS" = "2" || exit 1
grep -qxF "DIGEST_DEL_REGISTRO=$REG" "$D/02-respuesta.txt" || exit 1
grep -qxF "IMAGEN_DEL_DESPLIEGUE=$IMG" "$D/02-respuesta.txt" || exit 1
grep -qxF "REPLICAS_LISTAS=$LISTAS" "$D/02-respuesta.txt" || exit 1
PODS=$($K -n $NS get pods -o json 2>/dev/null | jq -c '[.items[] | select(.metadata.deletionTimestamp == null)]')
test "$(echo "$PODS" | jq 'length')" -ge 2 || exit 1
echo "$PODS" | jq -e '[.[] | (.spec.containers[], (.spec.initContainers[]? // empty)) | .image] | length > 0 and all(test("@sha256:[0-9a-f]{64}$"))' >/dev/null || exit 1
VIVOS=$(echo "$PODS" | jq -c '[.[] | select(.status.phase == "Running") | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))]')
test "$(echo "$VIVOS" | jq 'length')" -ge 2 || exit 1
for HUELLA in $(echo "$VIVOS" | jq -r '[.[].status.containerStatuses[0].imageID] | unique | .[]'); do
  case "$HUELLA" in *"@$REG") ;; *) exit 1 ;; esac
done
for TIPO in daemonsets statefulsets; do
  $K -n $NS get "$TIPO" -o json 2>/dev/null | jq -e '[.items[] | .spec.template.spec.containers[].image] | all(test("@sha256:[0-9a-f]{64}$"))' >/dev/null || exit 1
done
echo ok
