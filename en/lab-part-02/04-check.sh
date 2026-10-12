#!/usr/bin/env bash
# lab-part-02 step 4 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
KC="$HOME/cks-lab/p02/kubeconfig"
D="$HOME/cks-lab/p02"
K="kubectl --kubeconfig $KC"
NODO="cks-p02-control-plane"
COMO="--as=system:node:$NODO --as-group=system:nodes --as-group=system:authenticated"
test -f "$D/04-respuesta.txt" || exit 1
ASENTADO=no
for i in $(seq 1 30); do
  SALUD=$($K get --raw /healthz 2>/dev/null)
  FASE=$($K -n kube-system get pod kube-apiserver-$NODO -o jsonpath='{.status.phase}' 2>/dev/null)
  LISTO=$($K get node $NODO -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [ "$SALUD" = "ok" ] && [ "$FASE" = "Running" ] && [ "$LISTO" = "True" ]; then ASENTADO=si; break; fi
  sleep 6
done
test "$ASENTADO" = "si" || exit 1
ORDEN=$($K -n kube-system get pod kube-apiserver-$NODO -o jsonpath='{.spec.containers[0].command}' 2>/dev/null | tr ',' '\n')
BANDERA=$(echo "$ORDEN" | grep -o -- '--enable-admission-plugins=[^"]*' | head -1)
test -n "$BANDERA" || exit 1
PLUGINS=${BANDERA#*=}
echo "$PLUGINS" | tr ',' '\n' | grep -qx NodeRestriction || exit 1
APAGADOS=$(echo "$ORDEN" | grep -o -- '--disable-admission-plugins=[^"]*' | head -1)
if [ -n "$APAGADOS" ]; then
  echo "${APAGADOS#*=}" | tr ',' '\n' | grep -qx NodeRestriction && exit 1
fi
DIR=$($K get --raw /api/v1/nodes/$NODO/proxy/configz 2>/dev/null | grep -o '"staticPodPath":"[^"]*"' | sed 's/.*:"//;s/"$//')
test -n "$DIR" || exit 1
MANIFIESTO="$DIR/kube-apiserver.yaml"
docker exec "$NODO" sh -c "test -f '$MANIFIESTO'" || exit 1
docker exec "$NODO" sh -c "grep -q -- '--enable-admission-plugins=.*NodeRestriction' '$MANIFIESTO'" || exit 1
NEGADO=$($K label node "$NODO" node-restriction.kubernetes.io/calificacion-p02=si $COMO 2>&1)
$K label node "$NODO" node-restriction.kubernetes.io/calificacion-p02- >/dev/null 2>&1
echo "$NEGADO" | grep -q "is not allowed to modify labels" || exit 1
RAZON=$(echo "$NEGADO" | sed -n 's/^Error from server (\([A-Za-z]*\)).*/\1/p' | head -1)
test -n "$RAZON" || exit 1
PERMITIDO=$($K label node "$NODO" ejemplo.com/calificacion-p02=si --overwrite $COMO 2>&1)
$K label node "$NODO" ejemplo.com/calificacion-p02- >/dev/null 2>&1
echo "$PERMITIDO" | grep -q "labeled" || exit 1
for P in garita ronda-nocturna; do
  F=$($K -n porteria get pod $P -o jsonpath='{.status.phase}' 2>/dev/null)
  test "$F" = "Running" || exit 1
done
grep -qxF "BANDERA_DE_ADMISION=--enable-admission-plugins" "$D/04-respuesta.txt" || exit 1
grep -qxF "PLUGINS_HABILITADOS=$PLUGINS" "$D/04-respuesta.txt" || exit 1
grep -qxF "ARCHIVO_DEL_MANIFIESTO=$MANIFIESTO" "$D/04-respuesta.txt" || exit 1
grep -qxF "RESPUESTA_A_LA_ETIQUETA=$RAZON" "$D/04-respuesta.txt" || exit 1
echo ok
