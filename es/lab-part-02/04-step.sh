#!/usr/bin/env bash
# lab-part-02 step 4 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

KC="$HOME/cks-lab/p02/kubeconfig"
K="kubectl --kubeconfig $KC"
NODO="cks-p02-control-plane"
COMO="--as=system:node:$NODO --as-group=system:nodes --as-group=system:authenticated"
cd ~/cks-lab/p02

$K -n kube-system get pod kube-apiserver-$NODO \
  -o jsonpath='{.spec.containers[0].command}' | tr ',' '\n' | grep -i admission
$K get --raw /api/v1/nodes/$NODO/proxy/configz | grep -o '"staticPodPath":"[^"]*"'
docker exec "$NODO" sh -c 'grep -n -- "--enable-admission-plugins" /etc/kubernetes/manifests/kube-apiserver.yaml'

$K label node "$NODO" node-restriction.kubernetes.io/prueba=si $COMO
$K label node "$NODO" node-restriction.kubernetes.io/prueba- 2>/dev/null

docker exec "$NODO" sh -c \
  'sed -i "s/--enable-admission-plugins=LimitRanger/--enable-admission-plugins=NodeRestriction/" /etc/kubernetes/manifests/kube-apiserver.yaml'

for i in $(seq 1 40); do
  F=$($K -n kube-system get pod kube-apiserver-$NODO -o jsonpath='{.spec.containers[0].command}' 2>/dev/null \
      | tr ',' '\n' | grep -o -- '--enable-admission-plugins=[^"]*')
  case "$F" in *NodeRestriction*) echo "bandera viva: $F"; break;; esac
  sleep 5
done
$K get --raw /healthz; echo

$K label node "$NODO" node-restriction.kubernetes.io/prueba=si $COMO
$K label node "$NODO" ejemplo.com/prueba=si --overwrite $COMO
$K label node "$NODO" ejemplo.com/prueba- 2>/dev/null
# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/cks-lab/p02"
ERR=$($K label node "$NODO" node-restriction.kubernetes.io/prueba=si $COMO 2>&1 || true)
cat > "$D/04-respuesta.txt" <<RESP
BANDERA_DE_ADMISION=--enable-admission-plugins
PLUGINS_HABILITADOS=$($K -n kube-system get pod kube-apiserver-$NODO -o jsonpath='{.spec.containers[0].command}' | tr ',' '\n' | grep -o -- '--enable-admission-plugins=[^"]*' | cut -d= -f2)
ARCHIVO_DEL_MANIFIESTO=$($K get --raw /api/v1/nodes/$NODO/proxy/configz | jq -r '.kubeletconfig.staticPodPath')/kube-apiserver.yaml
RESPUESTA_A_LA_ETIQUETA=$(echo "$ERR" | grep -oE '\(([A-Za-z]+)\)' | head -1 | tr -d '()')
RESP
cat "$D/04-respuesta.txt"
