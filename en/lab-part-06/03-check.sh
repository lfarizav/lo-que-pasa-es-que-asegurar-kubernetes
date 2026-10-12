#!/usr/bin/env bash
# lab-part-06 step 3 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
W="$HOME/cks-lab/p06"; K="kubectl --kubeconfig $W/kubeconfig"; R="$W/03-respuesta.txt"
C="$W/bin/camaras"; KC="$W/kubeconfig"
test -f "$R" || exit 1
grep -qxF "REGLA=Terminal shell in container" "$R" || exit 1
grep -qxF "PRIORIDAD=Notice" "$R" || exit 1
grep -qxF "CAMPO_QUE_EXIGE_TERMINAL=proc.tty" "$R" || exit 1
test "$($K -n la-celaduria get ds falco -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)" = "1" || exit 1
test "$($K -n la-celaduria get ds falco -o jsonpath='{.status.numberReady}' 2>/dev/null)" = "1" || exit 1
test "$($K -n la-celaduria get pod porteria -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" || exit 1
CID=$($K -n la-celaduria get pod porteria \
  -o jsonpath='{.status.containerStatuses[0].containerID}' 2>/dev/null | sed 's#^containerd://##' | cut -c1-12)
test -n "$CID" || exit 1
grep -qxF "CONTENEDOR=$CID" "$R" || exit 1
"$C" 2>/dev/null | grep '^{' | jq -e --arg c "$CID" 'select(.rule=="Terminal shell in container"
  and .priority=="Notice" and .output_fields["container.id"]==$c)' >/dev/null 2>&1 || exit 1
VID=$($K -n la-celaduria get pod verificador \
  -o jsonpath='{.status.containerStatuses[0].containerID}' 2>/dev/null | sed 's#^containerd://##' | cut -c1-12)
test -n "$VID" || exit 1
ANTES=$("$C" 2>/dev/null | grep '^{' | jq -r --arg c "$VID" 'select(.rule=="Terminal shell in container"
  and .output_fields["container.id"]==$c) | .rule' | wc -l)
VIVA=no
for i in 1 2 3 4 5 6; do
  script -q -c "kubectl --kubeconfig $KC -n la-celaduria exec -it verificador -- sh -c 'echo sonda-de-calificacion'" /dev/null >/dev/null 2>&1 || true
  sleep 6
  AHORA=$("$C" 2>/dev/null | grep '^{' | jq -r --arg c "$VID" 'select(.rule=="Terminal shell in container"
    and .output_fields["container.id"]==$c) | .rule' | wc -l)
  if [ "$AHORA" -gt "$ANTES" ]; then VIVA=si; break; fi
done
test "$VIVA" = "si" || exit 1
echo ok
