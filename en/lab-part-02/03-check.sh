#!/usr/bin/env bash
# lab-part-02 step 3 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
KC="$HOME/cks-lab/p02/kubeconfig"
D="$HOME/cks-lab/p02"
K="kubectl --kubeconfig $KC"
NODO="cks-p02-control-plane"
test -f "$D/03-respuesta.txt" || exit 1
LISTO=$($K get node $NODO -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
test "$LISTO" = "True" || exit 1
CODIGO=$(docker exec "$NODO" sh -c 'curl -sk -o /dev/null -w "%{http_code}" --max-time 10 https://127.0.0.1:10250/pods' 2>/dev/null | tr -d '\r\n')
test "$CODIGO" = "401" || exit 1
CFG=$($K get --raw /api/v1/nodes/$NODO/proxy/configz 2>/dev/null)
echo "$CFG" | grep -q '"anonymous":{"enabled":false}' || exit 1
MODO=$(echo "$CFG" | grep -o '"authorization":{"mode":"[A-Za-z]*"' | sed 's/.*"mode":"//;s/"$//')
test "$MODO" = "Webhook" || exit 1
SOLOLECTURA=$(docker exec "$NODO" sh -c 'curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://127.0.0.1:10255/pods' 2>/dev/null | tr -d '\r\n')
test "$SOLOLECTURA" = "000" || exit 1
SIRVE=no
for i in $(seq 1 20); do
  $K -n porteria exec garita -- true >/dev/null 2>&1 && { SIRVE=si; break; }
  sleep 6
done
test "$SIRVE" = "si" || exit 1
for P in garita ronda-nocturna; do
  FASE=$($K -n porteria get pod $P -o jsonpath='{.status.phase}' 2>/dev/null)
  test "$FASE" = "Running" || exit 1
done
RUTA=$(docker exec "$NODO" sh -c 'tr "\0" "\n" < /proc/$(pgrep -x kubelet)/cmdline | grep -- "--config=" | sed "s/^--config=//"' 2>/dev/null | tr -d '\r\n')
test -n "$RUTA" || exit 1
docker exec "$NODO" sh -c "test -f '$RUTA'" || exit 1
grep -qxF "CODIGO_SIN_CREDENCIALES=$CODIGO" "$D/03-respuesta.txt" || exit 1
grep -qxF "ANONIMO_HABILITADO=false" "$D/03-respuesta.txt" || exit 1
grep -qxF "MODO_DE_AUTORIZACION=$MODO" "$D/03-respuesta.txt" || exit 1
grep -qxF "ARCHIVO_DE_CONFIGURACION=$RUTA" "$D/03-respuesta.txt" || exit 1
echo ok
