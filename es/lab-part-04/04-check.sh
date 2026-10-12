#!/usr/bin/env bash
# lab-part-04 step 4 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
KC="$HOME/cks-lab/p04/kubeconfig"
D="$HOME/cks-lab/p04"
test -f "$D/04-respuesta.txt" || exit 1

SRV=$(kubectl --kubeconfig "$KC" -n citofono get pod citofono -o jsonpath='{.status.phase}' 2>/dev/null)
test "$SRV" = "Running" || exit 1
CLI=$(kubectl --kubeconfig "$KC" -n citofono get pod vecino -o jsonpath='{.status.phase}' 2>/dev/null)
test "$CLI" = "Running" || exit 1

BUENO=""
for i in $(seq 1 20); do
  BUENO=$(kubectl --kubeconfig "$KC" -n citofono exec vecino -- \
    curl -s -o /dev/null -w '%{http_code}' --cacert /carnet/ca.crt \
    --cert /carnet/vecino.crt --key /carnet/vecino.key https://citofono:8443/ 2>/dev/null | tr -d '\r')
  [ "$BUENO" = "200" ] && break
  sleep 3
done
test "$BUENO" = "200" || exit 1

CUERPO=$(kubectl --kubeconfig "$KC" -n citofono exec vecino -- \
  curl -s --cacert /carnet/ca.crt --cert /carnet/vecino.crt --key /carnet/vecino.key https://citofono:8443/ 2>/dev/null)
echo "$CUERPO" | grep -q 'apartamento-303' || exit 1

SIN=$(kubectl --kubeconfig "$KC" -n citofono exec vecino -- \
  curl -s -o /dev/null -w '%{http_code}' --cacert /carnet/ca.crt https://citofono:8443/ 2>/dev/null | tr -d '\r')
test "$SIN" != "200" || exit 1
CUERPOSIN=$(kubectl --kubeconfig "$KC" -n citofono exec vecino -- \
  curl -s --cacert /carnet/ca.crt https://citofono:8443/ 2>/dev/null)
echo "$CUERPOSIN" | grep -q 'adelante' && exit 1

CALLE=$(kubectl --kubeconfig "$KC" -n citofono exec vecino -- \
  curl -s -o /dev/null -w '%{http_code}' --cacert /carnet/ca.crt \
  --cert /calle/impostor.crt --key /calle/impostor.key https://citofono:8443/ 2>/dev/null | tr -d '\r')
test "$CALLE" != "200" || exit 1

kubectl --kubeconfig "$KC" -n citofono exec citofono -- \
  grep -qE '^[[:space:]]*ssl_verify_client[[:space:]]+on;' /etc/nginx/conf.d/citofono.conf || exit 1
kubectl --kubeconfig "$KC" -n citofono exec citofono -- \
  grep -qE '^[[:space:]]*ssl_client_certificate[[:space:]]+/etc/nginx/ca/ca\.crt;' /etc/nginx/conf.d/citofono.conf || exit 1

grep -qxF "SIN_CARNET=$SIN" "$D/04-respuesta.txt" || exit 1
grep -qxF "CARNET_DE_LA_CALLE=$CALLE" "$D/04-respuesta.txt" || exit 1
grep -qxF "CON_CARNET=$BUENO" "$D/04-respuesta.txt" || exit 1
echo ok
