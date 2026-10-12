#!/usr/bin/env bash
# lab-part-06 step 1 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

W="$HOME/cks-lab/p06"; K="kubectl --kubeconfig $W/kubeconfig"

# 1. La accion que va a quedar anotada.
$K -n la-porteria create secret generic libro-de-minuta \
  --from-literal=clave=turno-de-la-noche
sleep 3

# 2. Buscarla en la minuta. Un renglon por evento, en JSON.
"$W/bin/minuta" | jq -c 'select(.objectRef.name=="libro-de-minuta")' | head -3

# 3. Los campos que pide el entregable, uno por columna.
"$W/bin/minuta" | jq -r 'select(.objectRef.name=="libro-de-minuta" and .verb=="create")
  | [.user.username, (.user.groups|join(",")), .verb, .objectRef.resource, .level, .stage] | @tsv'

# 4. Por que ese nivel y no otro: la politica que el API server esta aplicando.
docker exec cks-p06-control-plane cat /etc/kubernetes/audit/policy.yaml

# 5. Las banderas con las que el API server abrio la minuta.
$K -n kube-system get pod kube-apiserver-cks-p06-control-plane \
  -o jsonpath='{range .spec.containers[0].command[*]}{@}{"\n"}{end}' | grep -- '--audit'

# The answer file the lab asks you to type, written from the live audit log:
EV=$("$W/bin/minuta" | jq -c 'select(.objectRef.name=="libro-de-minuta" and .verb=="create")' | head -1)
cat > "$W/01-respuesta.txt" <<RESP
USUARIO=$(echo "$EV" | jq -r .user.username)
GRUPO=$(echo "$EV" | jq -r '[.user.groups[] | select(. != "system:authenticated")][0]')
VERBO=$(echo "$EV" | jq -r .verb)
RECURSO=$(echo "$EV" | jq -r .objectRef.resource)
NIVEL=$(echo "$EV" | jq -r .level)
RESP
cat "$W/01-respuesta.txt"
