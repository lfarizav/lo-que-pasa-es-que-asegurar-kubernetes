#!/usr/bin/env bash
# lab-part-06 step 1 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
W="$HOME/cks-lab/p06"; K="kubectl --kubeconfig $W/kubeconfig"; R="$W/01-respuesta.txt"
M="$W/bin/minuta"
test -f "$R" || exit 1
grep -qxF "USUARIO=kubernetes-admin" "$R" || exit 1
grep -qxF "GRUPO=kubeadm:cluster-admins" "$R" || exit 1
grep -qxF "VERBO=create" "$R" || exit 1
grep -qxF "RECURSO=secrets" "$R" || exit 1
grep -qxF "NIVEL=RequestResponse" "$R" || exit 1
$K -n la-porteria get secret libro-de-minuta >/dev/null 2>&1 || exit 1
"$M" 2>/dev/null | jq -e 'select(.objectRef.name=="libro-de-minuta" and .verb=="create"
  and .objectRef.resource=="secrets" and .objectRef.namespace=="la-porteria"
  and .level=="RequestResponse" and .stage=="ResponseComplete"
  and .user.username=="kubernetes-admin"
  and (.user.groups|index("kubeadm:cluster-admins")))' >/dev/null 2>&1 || exit 1
CMD=$($K -n kube-system get pod kube-apiserver-cks-p06-control-plane \
  -o jsonpath='{range .spec.containers[0].command[*]}{@}{"\n"}{end}' 2>/dev/null)
echo "$CMD" | grep -q -- '--audit-policy-file=' || exit 1
echo "$CMD" | grep -q -- '--audit-log-path=' || exit 1
SELLO="sello-de-turno-$(date +%s)"
$K -n la-porteria create configmap "$SELLO" --from-literal=x=y >/dev/null 2>&1 || exit 1
VISTO=no
for i in 1 2 3 4 5 6 7 8 9 10; do
  if "$M" 2>/dev/null | jq -e --arg n "$SELLO" 'select(.objectRef.name==$n and .verb=="create")' >/dev/null 2>&1; then
    VISTO=si; break
  fi
  sleep 3
done
$K -n la-porteria delete configmap "$SELLO" >/dev/null 2>&1
test "$VISTO" = "si" || exit 1
echo ok
