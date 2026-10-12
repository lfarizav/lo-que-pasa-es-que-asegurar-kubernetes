#!/usr/bin/env bash
# lab-part-03 step 1 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
KC="$HOME/cks-lab/p03/kubeconfig"
D="$HOME/cks-lab/p03"
test -f "$D/01-respuesta.txt" || exit 1

FASE=$(kubectl --kubeconfig "$KC" -n conjunto get pod celaduria-con-uniforme -o jsonpath='{.status.phase}' 2>/dev/null)
test "$FASE" = "Running" || exit 1
LISTO=$(kubectl --kubeconfig "$KC" -n conjunto get pod celaduria-con-uniforme -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
test "$LISTO" = "True" || exit 1

TIPO_POD=$(kubectl --kubeconfig "$KC" -n conjunto get pod celaduria-con-uniforme -o jsonpath='{.spec.securityContext.seccompProfile.type}' 2>/dev/null)
TIPO_CTR=$(kubectl --kubeconfig "$KC" -n conjunto get pod celaduria-con-uniforme -o jsonpath='{.spec.containers[0].securityContext.seccompProfile.type}' 2>/dev/null)
test "$TIPO_POD" = "RuntimeDefault" -o "$TIPO_CTR" = "RuntimeDefault" || exit 1

GFASE=$(kubectl --kubeconfig "$KC" -n conjunto get pod celaduria-sin-uniforme -o jsonpath='{.status.phase}' 2>/dev/null)
test "$GFASE" = "Running" || exit 1
GTIPO=$(kubectl --kubeconfig "$KC" -n conjunto get pod celaduria-sin-uniforme -o jsonpath='{.spec.securityContext.seccompProfile.type}' 2>/dev/null)
test "$GTIPO" = "Unconfined" || exit 1

MODO_CON=$(kubectl --kubeconfig "$KC" -n conjunto exec celaduria-con-uniforme -- sh -c 'grep ^Seccomp: /proc/1/status' 2>/dev/null | awk '{print $2}')
test "$MODO_CON" = "2" || exit 1
MODO_SIN=$(kubectl --kubeconfig "$KC" -n conjunto exec celaduria-sin-uniforme -- sh -c 'grep ^Seccomp: /proc/1/status' 2>/dev/null | awk '{print $2}')
test "$MODO_SIN" = "0" || exit 1

kubectl --kubeconfig "$KC" -n conjunto exec celaduria-sin-uniforme -- unshare -U true >/dev/null 2>&1 || exit 1
if kubectl --kubeconfig "$KC" -n conjunto exec celaduria-con-uniforme -- unshare -U true >/dev/null 2>&1; then exit 1; fi

BANDERA=$(kubectl --kubeconfig "$KC" -n conjunto exec celaduria-con-uniforme -- sh -c 'unshare -U true' 2>&1 | sed -n 's/.*unshare(\(0x[0-9a-fA-F]*\)).*/\1/p' | head -1)
test -n "$BANDERA" || exit 1

grep -qxF "MODO_SECCOMP_CON_UNIFORME=$MODO_CON" "$D/01-respuesta.txt" || exit 1
grep -qxF "MODO_SECCOMP_SIN_UNIFORME=$MODO_SIN" "$D/01-respuesta.txt" || exit 1
grep -qxF "LLAMADA_BLOQUEADA=$BANDERA" "$D/01-respuesta.txt" || exit 1
echo ok
