#!/usr/bin/env bash
# lab-part-06 step 2 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
W="$HOME/cks-lab/p06"; K="kubectl --kubeconfig $W/kubeconfig"; R="$W/02-respuesta.txt"
M="$W/bin/minuta"; SA="system:serviceaccount:la-bodega:auxiliar-de-turno"
FILTRADO="combinacion-7431-de-la-caja-fuerte"
test -f "$R" || exit 1
grep -qxF "CUENTA=$SA" "$R" || exit 1
grep -qxF "SECRETO=la-caja-fuerte" "$R" || exit 1
grep -qxF "CODIGO_PRIMER_INTENTO=403" "$R" || exit 1
grep -qxF "ROLEBINDING=prestamo-de-llaves" "$R" || exit 1
grep -qxF "VALOR_FILTRADO=$FILTRADO" "$R" || exit 1
"$M" 2>/dev/null | jq -e --arg u "$SA" 'select(.user.username==$u and .verb=="get"
  and .objectRef.name=="la-caja-fuerte" and .responseStatus.code==403)' >/dev/null 2>&1 || exit 1
"$M" 2>/dev/null | jq -e --arg u "$SA" 'select(.user.username==$u and .verb=="get"
  and .objectRef.name=="la-caja-fuerte" and .responseStatus.code==200
  and .level=="RequestResponse")' >/dev/null 2>&1 || exit 1
$K -n la-bodega get serviceaccount auxiliar-de-turno >/dev/null 2>&1 || exit 1
$K -n la-bodega get serviceaccount auxiliar-de-dia >/dev/null 2>&1 || exit 1
test "$($K auth can-i get secrets -n la-bodega --as="$SA" 2>/dev/null)" = "no" || exit 1
test "$($K auth can-i list secrets -n la-bodega --as="$SA" 2>/dev/null)" = "no" || exit 1
test "$($K auth can-i get configmaps -n la-bodega \
  --as=system:serviceaccount:la-bodega:auxiliar-de-dia 2>/dev/null)" = "yes" || exit 1
NUEVA=$($K -n la-bodega get secret la-caja-fuerte -o jsonpath='{.data.clave}' 2>/dev/null | base64 -d 2>/dev/null)
test -n "$NUEVA" || exit 1
test "$NUEVA" != "$FILTRADO" || exit 1
echo ok
