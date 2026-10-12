#!/usr/bin/env bash
# lab-part-03 step 4 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
KC="$HOME/cks-lab/p03/kubeconfig"
D="$HOME/cks-lab/p03"
NODO="cks-p03-control-plane"
test -f "$D/04-respuesta.txt" || exit 1

SS=$(docker exec "$NODO" ss -H -lntp 2>/dev/null)
test -n "$SS" || exit 1

EXTRA=$(printf '%s\n' "$SS" | awk '{n=split($4,p,":"); port=p[n]; addr=substr($4,1,length($4)-length(port)-1); if (addr !~ /^127\./ && addr != "[::1]") print port}' | grep -vxE '2379|2380|6443|10250|10256')
test -z "$EXTRA" || exit 1

HABILITADAS=$(docker exec "$NODO" systemctl list-unit-files --type=socket --no-pager 2>/dev/null | awk '$2=="enabled" {print $1}')
test -z "$HABILITADAS" || exit 1

for P in 2379 2380 6443 10250 10256 10257 10259; do
  LINEA=$(printf '%s\n' "$SS" | awk -v p=":$P" 'index($4, p) == length($4) - length(p) + 1' | head -1)
  test -n "$LINEA" || exit 1
  PROC=$(printf '%s' "$LINEA" | sed -n 's/.*users:((\"\([^\"]*\)\".*/\1/p')
  test -n "$PROC" || exit 1
  FILA=$(grep -m1 "^$P|$PROC|" "$D/04-respuesta.txt")
  test -n "$FILA" || exit 1
  JUST=$(printf '%s' "$FILA" | cut -d'|' -f3-)
  test ${#JUST} -ge 25 || exit 1
done

docker exec "$NODO" systemctl is-active kubelet 2>/dev/null | grep -qx active || exit 1
CODIGO=$(docker exec "$NODO" curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:10248/healthz 2>/dev/null)
test "$CODIGO" = "200" || exit 1
LISTO=$(kubectl --kubeconfig "$KC" get node cks-p03-control-plane -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
test "$LISTO" = "True" || exit 1
echo ok
