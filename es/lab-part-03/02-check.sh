#!/usr/bin/env bash
# lab-part-03 step 2 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
KC="$HOME/cks-lab/p03/kubeconfig"
D="$HOME/cks-lab/p03"
NODO="cks-p03-control-plane"
test -f "$D/02-respuesta.txt" || exit 1

FASE=$(kubectl --kubeconfig "$KC" -n conjunto get pod tienda-del-conjunto -o jsonpath='{.status.phase}' 2>/dev/null)
test "$FASE" = "Running" || exit 1
LISTO=$(kubectl --kubeconfig "$KC" -n conjunto get pod tienda-del-conjunto -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
test "$LISTO" = "True" || exit 1

TIPO=$(kubectl --kubeconfig "$KC" -n conjunto get pod tienda-del-conjunto -o jsonpath='{.spec.securityContext.seccompProfile.type}' 2>/dev/null)
RUTA=$(kubectl --kubeconfig "$KC" -n conjunto get pod tienda-del-conjunto -o jsonpath='{.spec.securityContext.seccompProfile.localhostProfile}' 2>/dev/null)
if [ "$TIPO" != "Localhost" ]; then
  TIPO=$(kubectl --kubeconfig "$KC" -n conjunto get pod tienda-del-conjunto -o jsonpath='{.spec.containers[0].securityContext.seccompProfile.type}' 2>/dev/null)
  RUTA=$(kubectl --kubeconfig "$KC" -n conjunto get pod tienda-del-conjunto -o jsonpath='{.spec.containers[0].securityContext.seccompProfile.localhostProfile}' 2>/dev/null)
fi
test "$TIPO" = "Localhost" || exit 1
test "$RUTA" = "profiles/candado-del-local.json" || exit 1

MODO=$(kubectl --kubeconfig "$KC" -n conjunto exec tienda-del-conjunto -- sh -c 'grep ^Seccomp: /proc/1/status' 2>/dev/null | awk '{print $2}')
test "$MODO" = "2" || exit 1

kubectl --kubeconfig "$KC" -n conjunto exec tienda-del-conjunto -- sh -c 'touch /tmp/calificacion-p02' >/dev/null 2>&1 || exit 1
if kubectl --kubeconfig "$KC" -n conjunto exec tienda-del-conjunto -- sh -c 'chmod 700 /tmp/calificacion-p02' >/dev/null 2>&1; then exit 1; fi

PJ=$(docker exec "$NODO" cat "/var/lib/kubelet/seccomp/$RUTA" 2>/dev/null)
test -n "$PJ" || exit 1
PLANO=$(printf '%s' "$PJ" | tr -d ' \t\n')
printf '%s' "$PLANO" | grep -q 'chmod' || exit 1
printf '%s' "$PLANO" | grep -qE 'SCMP_ACT_(ERRNO|KILL|KILL_PROCESS|KILL_THREAD|TRAP)' || exit 1
ACC=$(printf '%s' "$PLANO" | sed -n 's/.*"defaultAction":"\([A-Z_]*\)".*/\1/p')
test -n "$ACC" || exit 1

grep -qxF "RUTA_DEL_PERFIL=$RUTA" "$D/02-respuesta.txt" || exit 1
grep -qxF "ACCION_POR_DEFECTO=$ACC" "$D/02-respuesta.txt" || exit 1
echo ok
