#!/usr/bin/env bash
# lab-part-03 step 3 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
KC="$HOME/cks-lab/p03/kubeconfig"
D="$HOME/cks-lab/p03"
NODO="cks-p03-control-plane"
test -f "$D/03-respuesta.txt" || exit 1

FASE=$(kubectl --kubeconfig "$KC" -n conjunto get pod bodega -o jsonpath='{.status.phase}' 2>/dev/null)
test "$FASE" = "Running" || exit 1
LISTO=$(kubectl --kubeconfig "$KC" -n conjunto get pod bodega -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
test "$LISTO" = "True" || exit 1

TIPO=$(kubectl --kubeconfig "$KC" -n conjunto get pod bodega -o jsonpath='{.spec.containers[0].securityContext.appArmorProfile.type}' 2>/dev/null)
NOMBRE=$(kubectl --kubeconfig "$KC" -n conjunto get pod bodega -o jsonpath='{.spec.containers[0].securityContext.appArmorProfile.localhostProfile}' 2>/dev/null)
if [ "$TIPO" != "Localhost" ]; then
  TIPO=$(kubectl --kubeconfig "$KC" -n conjunto get pod bodega -o jsonpath='{.spec.securityContext.appArmorProfile.type}' 2>/dev/null)
  NOMBRE=$(kubectl --kubeconfig "$KC" -n conjunto get pod bodega -o jsonpath='{.spec.securityContext.appArmorProfile.localhostProfile}' 2>/dev/null)
fi
test "$TIPO" = "Localhost" || exit 1
test "$NOMBRE" = "cks-p03-bodega-sin-lapicero" || exit 1

VIVO=$(kubectl --kubeconfig "$KC" -n conjunto exec bodega -- cat /proc/1/attr/current 2>/dev/null | tr -d '\0' | tr -d '\n')
test "$VIVO" = "$NOMBRE (enforce)" || exit 1

kubectl --kubeconfig "$KC" -n conjunto exec bodega -- cat /etc/hostname >/dev/null 2>&1 || exit 1
if kubectl --kubeconfig "$KC" -n conjunto exec bodega -- touch /tmp/calificacion-p03 >/dev/null 2>&1; then exit 1; fi

LINEA=$(docker exec "$NODO" sh -c "grep -m1 '^$NOMBRE (' /sys/kernel/security/apparmor/profiles" 2>/dev/null)
test -n "$LINEA" || exit 1
MODO=$(printf '%s' "$LINEA" | sed -n 's/.*(\([a-z]*\)).*/\1/p')
test "$MODO" = "enforce" || exit 1

grep -qxF "PERFIL_DEL_PROCESO=$VIVO" "$D/03-respuesta.txt" || exit 1
grep -qxF "MODO_EN_EL_NODO=$MODO" "$D/03-respuesta.txt" || exit 1
echo ok
