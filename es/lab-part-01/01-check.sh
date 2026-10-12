#!/usr/bin/env bash
# lab-part-01 step 1 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/cks-lab/p01"
K="kubectl --kubeconfig $D/kubeconfig"
NS=la-torre-tres
FQDN=citofono-301.$NS.svc.cluster.local
test -f "$D/01-respuesta.txt" || exit 1
$K -n $NS get pod el-apartamento-301 -o jsonpath='{.metadata.labels.rol}' 2>/dev/null | grep -qx apartamento || exit 1
$K -n $NS get pod el-vecino-autorizado -o jsonpath='{.metadata.labels.visita}' 2>/dev/null | grep -qx autorizada || exit 1
$K -n $NS get pod el-desconocido-del-portal -o jsonpath='{.metadata.labels.visita}' 2>/dev/null | grep -qx negada || exit 1
$K -n $NS get svc citofono-301 -o jsonpath='{.spec.ports[0].port}' 2>/dev/null | grep -qx 80 || exit 1
NEGACION=""
for NP in $($K -n $NS get netpol -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  test "$($K -n $NS get netpol "$NP" -o jsonpath='{.spec.podSelector}' 2>/dev/null)" = "{}" || continue
  PT=$($K -n $NS get netpol "$NP" -o jsonpath='{.spec.policyTypes[*]}' 2>/dev/null)
  echo "$PT" | grep -qw Ingress || continue
  echo "$PT" | grep -qw Egress || continue
  test -z "$($K -n $NS get netpol "$NP" -o jsonpath='{.spec.ingress}' 2>/dev/null)" || continue
  test -z "$($K -n $NS get netpol "$NP" -o jsonpath='{.spec.egress}' 2>/dev/null)" || continue
  NEGACION="$NP"; break
done
test -n "$NEGACION" || exit 1
$K -n $NS exec el-vecino-autorizado -- wget -q -T 10 -O- "http://$FQDN" >/dev/null 2>&1 || exit 1
DESTINO=$($K -n $NS get pod el-apartamento-301 -o jsonpath='{.status.podIP}' 2>/dev/null)
test -n "$DESTINO" || exit 1
if $K -n $NS exec el-desconocido-del-portal -- wget -q -T 10 -O- "http://$DESTINO" >/dev/null 2>&1; then exit 1; fi
if $K -n $NS exec el-desconocido-del-portal -- wget -q -T 10 -O- "http://$FQDN" >/dev/null 2>&1; then exit 1; fi
grep -qxF "SALIDA_VECINO=0" "$D/01-respuesta.txt" || exit 1
SD=$(grep -oP '(?<=SALIDA_DESCONOCIDO=).*' "$D/01-respuesta.txt")
test -n "$SD" || exit 1
test "$SD" != "0" || exit 1
NPOL=$($K -n $NS get netpol -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w)
grep -qxF "POLITICAS_EN_LA_TORRE=$NPOL" "$D/01-respuesta.txt" || exit 1
echo ok
