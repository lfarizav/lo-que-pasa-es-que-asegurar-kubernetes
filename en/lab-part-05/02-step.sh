#!/usr/bin/env bash
# lab-part-05 step 2 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

LAB="$HOME/cks-lab/p05"
K="kubectl --kubeconfig $LAB/kubeconfig --context kind-cks-p05"
ACEPTA='application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'

$K -n la-vitrina get deploy la-vitrina -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
$K -n la-vitrina get pods -o jsonpath='{range .items[*]}{.metadata.name}{" imageID="}{.status.containerStatuses[0].imageID}{"\n"}{end}'

curl -sI -H "Accept: $ACEPTA" http://127.0.0.1:5065/v2/tienda/pan/manifests/v1
DIG=$(curl -sI -H "Accept: $ACEPTA" http://127.0.0.1:5065/v2/tienda/pan/manifests/v1 \
      | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}')
echo "digest que el registro reporta hoy para el tag v1: $DIG"

$K -n la-vitrina set image deployment/la-vitrina \
  tienda="cks-p05-registry:5000/tienda/pan@$DIG"
$K -n la-vitrina rollout status deployment/la-vitrina --timeout=180s

IMG=$($K -n la-vitrina get deploy la-vitrina -o jsonpath='{.spec.template.spec.containers[0].image}')
LISTAS=$($K -n la-vitrina get deploy la-vitrina -o jsonpath='{.status.readyReplicas}')
$K -n la-vitrina get pods -o jsonpath='{range .items[*]}{.metadata.name}{" imageID="}{.status.containerStatuses[0].imageID}{"\n"}{end}'

printf 'DIGEST_DEL_REGISTRO=%s\nIMAGEN_DEL_DESPLIEGUE=%s\nREPLICAS_LISTAS=%s\n' \
  "$DIG" "$IMG" "$LISTAS" > "$LAB/02-respuesta.txt"
cat "$LAB/02-respuesta.txt"
