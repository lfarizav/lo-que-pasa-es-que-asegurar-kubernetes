#!/usr/bin/env bash
# lab-part-02 step 1 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
KC="$HOME/cks-lab/p02/kubeconfig"
D="$HOME/cks-lab/p02"
K="kubectl --kubeconfig $KC"
SA="system:serviceaccount:porteria:celador-de-turno"
test -f "$D/01-respuesta.txt" || exit 1
$K -n porteria get serviceaccount celador-de-turno >/dev/null 2>&1 || exit 1
for V in get list watch; do
  R=$($K auth can-i $V pods -n porteria --as="$SA" 2>/dev/null)
  test "$R" = "yes" || exit 1
done
for V in get list; do
  R=$($K auth can-i $V configmaps -n porteria --as="$SA" 2>/dev/null)
  test "$R" = "yes" || exit 1
done
R=$($K auth can-i watch configmaps -n porteria --as="$SA" 2>/dev/null)
test "$R" = "no" || exit 1
for V in create update patch delete deletecollection; do
  R=$($K auth can-i $V pods -n porteria --as="$SA" 2>/dev/null)
  test "$R" = "no" || exit 1
  R=$($K auth can-i $V configmaps -n porteria --as="$SA" 2>/dev/null)
  test "$R" = "no" || exit 1
done
for V in get list watch create update patch delete; do
  R=$($K auth can-i $V secrets -n porteria --as="$SA" 2>/dev/null)
  test "$R" = "no" || exit 1
done
R=$($K auth can-i create pods --subresource=exec -n porteria --as="$SA" 2>/dev/null)
test "$R" = "no" || exit 1
R=$($K auth can-i list pods -n kube-system --as="$SA" 2>/dev/null)
test "$R" = "no" || exit 1
R=$($K auth can-i list pods --all-namespaces --as="$SA" 2>/dev/null)
test "$R" = "no" || exit 1
R=$($K auth can-i '*' '*' --all-namespaces --as="$SA" 2>/dev/null)
test "$R" = "no" || exit 1
CRB=$($K get clusterrolebindings -o jsonpath='{range .items[*]}{range .subjects[*]}{.kind}/{.namespace}/{.name}{"\n"}{end}{end}' 2>/dev/null)
echo "$CRB" | grep -qx 'ServiceAccount/porteria/celador-de-turno' && exit 1
LISTO=$($K -n porteria get pod garita -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
test "$LISTO" = "True" || exit 1
CUENTA=$($K -n porteria get pod garita -o jsonpath='{.spec.serviceAccountName}' 2>/dev/null)
test "$CUENTA" = "celador-de-turno" || exit 1
AUTO=$($K -n porteria get pod garita -o jsonpath='{.spec.automountServiceAccountToken}' 2>/dev/null)
test "$AUTO" != "false" || exit 1
sondear() {
  RESP=""
  for INTENTO in $(seq 1 8); do
    RESP=$($K -n porteria exec garita -- sh -c 'T=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token); wget -q -S -T 10 -O /dev/null --no-check-certificate --header="Authorization: Bearer $T" "https://kubernetes.default.svc/'"$1"'" 2>&1 | grep -m1 -oE "HTTP/1.1 [0-9]+"' 2>/dev/null | tr -d '\r\n')
    [ -n "$RESP" ] && break
    sleep 5
  done
  echo "$RESP"
}
PODS=$(sondear "api/v1/namespaces/porteria/pods")
test "$PODS" = "HTTP/1.1 200" || exit 1
TURNOS=$(sondear "api/v1/namespaces/porteria/configmaps/turnos-del-mes")
test "$TURNOS" = "HTTP/1.1 200" || exit 1
REJA=$(sondear "api/v1/namespaces/porteria/secrets/clave-de-la-reja")
test "$REJA" = "HTTP/1.1 403" || exit 1
CODIGO=${REJA##* }
grep -qxF "CUENTA_DE_LA_GARITA=$CUENTA" "$D/01-respuesta.txt" || exit 1
grep -qxF "PUEDE_LISTAR_PODS=yes" "$D/01-respuesta.txt" || exit 1
grep -qxF "PUEDE_BORRAR_PODS=no" "$D/01-respuesta.txt" || exit 1
grep -qxF "PUEDE_LEER_SECRETS=no" "$D/01-respuesta.txt" || exit 1
grep -qxF "CODIGO_EN_LOS_SECRETS=$CODIGO" "$D/01-respuesta.txt" || exit 1
echo ok
