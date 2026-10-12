#!/usr/bin/env bash
# lab-part-04 step 3 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
KC="$HOME/cks-lab/p04/kubeconfig"
D="$HOME/cks-lab/p04"
test -f "$D/03-respuesta.txt" || exit 1

FASE=$(kubectl --kubeconfig "$KC" -n apartamento-303 get pod empleado -o jsonpath='{.status.phase}' 2>/dev/null)
test "$FASE" = "Running" || exit 1
LISTO=$(kubectl --kubeconfig "$KC" -n apartamento-303 get pod empleado -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
test "$LISTO" = "True" || exit 1

RONR=$(kubectl --kubeconfig "$KC" -n apartamento-303 get pod empleado -o jsonpath='{.spec.securityContext.runAsNonRoot}{.spec.containers[0].securityContext.runAsNonRoot}' 2>/dev/null)
echo "$RONR" | grep -q true || exit 1
ROFS=$(kubectl --kubeconfig "$KC" -n apartamento-303 get pod empleado -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null)
test "$ROFS" = "true" || exit 1
DROPS=$(kubectl --kubeconfig "$KC" -n apartamento-303 get pod empleado -o jsonpath='{.spec.containers[0].securityContext.capabilities.drop[*]}' 2>/dev/null)
echo "$DROPS" | tr ' ' '\n' | grep -qx ALL || exit 1

UID_VIVO=$(kubectl --kubeconfig "$KC" -n apartamento-303 exec empleado -- id -u 2>/dev/null | tr -d '\r')
echo "$UID_VIVO" | grep -qE '^[0-9]+$' || exit 1
test "$UID_VIVO" != "0" || exit 1

CAPEFF=$(kubectl --kubeconfig "$KC" -n apartamento-303 exec empleado -- sh -c 'grep ^CapEff /proc/1/status' 2>/dev/null | awk '{print $2}' | tr -d '\r')
test "$CAPEFF" = "0000000000000000" || exit 1

if kubectl --kubeconfig "$KC" -n apartamento-303 exec empleado -- sh -c 'touch /sonda-de-calificacion-en-la-raiz' >/dev/null 2>&1; then
  kubectl --kubeconfig "$KC" -n apartamento-303 exec empleado -- sh -c 'rm -f /sonda-de-calificacion-en-la-raiz' >/dev/null 2>&1
  exit 1
fi

PRIMERA=$(kubectl --kubeconfig "$KC" -n apartamento-303 exec empleado -- cat /tmp/turno.txt 2>/dev/null | tr -d '\r')
test -n "$PRIMERA" || exit 1
sleep 5
SEGUNDA=$(kubectl --kubeconfig "$KC" -n apartamento-303 exec empleado -- cat /tmp/turno.txt 2>/dev/null | tr -d '\r')
test -n "$SEGUNDA" || exit 1
test "$PRIMERA" != "$SEGUNDA" || exit 1

grep -qxF "UID_DEL_PROCESO=$UID_VIVO" "$D/03-respuesta.txt" || exit 1
grep -qxF "CAPEFF_DEL_PROCESO=$CAPEFF" "$D/03-respuesta.txt" || exit 1
grep -qxF "ESCRITURA_EN_LA_RAIZ=denegada" "$D/03-respuesta.txt" || exit 1
echo ok
