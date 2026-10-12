#!/usr/bin/env bash
# lab-part-06 step 3 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

W="$HOME/cks-lab/p06"; K="kubectl --kubeconfig $W/kubeconfig"

# 1. Las camaras estan prendidas y cual es el archivo donde escriben.
$K -n la-celaduria get ds falco
$K -n la-celaduria logs ds/falco | head -4

# 2. La condicion de la regla, leida en el propio archivo de reglas de Falco.
$K -n la-celaduria exec ds/falco -- \
  sh -c "grep -A 14 '^- rule: Terminal shell in container' /etc/falco/falco_rules.yaml"

# 3. Primer intento SIN terminal: la regla no dispara, y ese es el punto del paso.
$K -n la-celaduria exec porteria -- sh -c 'id'
sleep 8
"$W/bin/camaras" | grep '^{' | jq -r 'select(.rule=="Terminal shell in container")|.rule' | wc -l

# 4. Segundo intento CON terminal asignada. En una sesion interactiva basta
#    kubectl exec -it; desde un script se le pide una terminal a script(1).
script -q -c "kubectl --kubeconfig $W/kubeconfig -n la-celaduria exec -it porteria -- sh -c 'id'" /dev/null
sleep 10

# 5. La alerta, y el contenedor al que apunta.
"$W/bin/camaras" | grep '^{' | jq -c 'select(.rule=="Terminal shell in container")
  | {rule, priority, cid: .output_fields["container.id"], cmd: .output_fields["proc.cmdline"]}'

# 6. Traducir ese id de contenedor a un Pod con nombre y apellido.
$K -n la-celaduria get pod porteria \
  -o jsonpath='{.status.containerStatuses[0].containerID}{"\n"}'

# The answer file the lab asks you to type, written from the live Falco output:
AL=$("$W/bin/camaras" | grep '^{' | jq -c 'select(.rule=="Terminal shell in container")' | tail -1)
cat > "$W/03-respuesta.txt" <<RESP
REGLA=$(echo "$AL" | jq -r .rule)
PRIORIDAD=$(echo "$AL" | jq -r .priority)
CAMPO_QUE_EXIGE_TERMINAL=proc.tty
CONTENEDOR=$(echo "$AL" | jq -r '.output_fields["container.id"]' | sed 's#containerd://##' | cut -c1-12)
RESP
cat "$W/03-respuesta.txt"
