#!/usr/bin/env bash
# lab-part-01 step 3 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/cks-lab/p01"
K="kubectl --kubeconfig $D/kubeconfig"
T="$D/.calificacion"
NS=la-porteria
test -f "$D/03-respuesta.txt" || exit 1
mkdir -p "$T" || exit 1
ING=""
for I in $($K -n $NS get ingress -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  test -n "$($K -n $NS get ingress "$I" -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null)" && ING="$I" && break
done
test -n "$ING" || exit 1
CLASE=$($K -n $NS get ingress "$ING" -o jsonpath='{.spec.ingressClassName}' 2>/dev/null)
test -n "$CLASE" || exit 1
$K get ingressclass "$CLASE" -o jsonpath='{.spec.controller}' 2>/dev/null | grep -qx 'k8s.io/ingress-nginx' || exit 1
$K -n ingress-nginx get deploy ingress-nginx-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -qE '^[1-9][0-9]*$' || exit 1
HOST=$($K -n $NS get ingress "$ING" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
test -n "$HOST" || exit 1
$K -n $NS get ingress "$ING" -o jsonpath='{.spec.tls[0].hosts[*]}' 2>/dev/null | grep -qw "$HOST" || exit 1
SECRETO=$($K -n $NS get ingress "$ING" -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null)
$K -n $NS get secret "$SECRETO" -o jsonpath='{.type}' 2>/dev/null | grep -qx 'kubernetes.io/tls' || exit 1
BACK=$($K -n $NS get ingress "$ING" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}' 2>/dev/null)
test "$BACK" = "citofono" || exit 1
JP_LISTOS='{range .items[*]}{range .endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{"\n"}{end}{end}'
$K -n $NS get endpointslices -l "kubernetes.io/service-name=citofono" -o jsonpath="$JP_LISTOS" 2>/dev/null | grep -q . || exit 1
$K -n $NS get secret "$SECRETO" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > "$T/cert-del-secret.pem" 2>/dev/null
test -s "$T/cert-del-secret.pem" || exit 1
HUELLA_SECRETO=$(openssl x509 -in "$T/cert-del-secret.pem" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
test -n "$HUELLA_SECRETO" || exit 1
HUELLA_SERVIDA=""
CODIGO=""
for _ in $(seq 1 30); do
  HUELLA_SERVIDA=$(openssl s_client -connect 127.0.0.1:8449 -servername "$HOST" </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
  CODIGO=$(curl -sSk -o /dev/null -w '%{http_code}' --max-time 15 --resolve "$HOST:8449:127.0.0.1" "https://$HOST:8449/" 2>/dev/null)
  test "$HUELLA_SERVIDA" = "$HUELLA_SECRETO" && test "$CODIGO" = "200" && break
  sleep 2
done
test -n "$HUELLA_SERVIDA" || exit 1
test "$HUELLA_SERVIDA" = "$HUELLA_SECRETO" || exit 1
test "$CODIGO" = "200" || exit 1
curl -sSk --max-time 15 --resolve "$HOST:8449:127.0.0.1" "https://$HOST:8449/" 2>/dev/null | grep -qF "LA PORTERIA CON CEDULA VERIFICADA" || exit 1
grep -qxF "HUELLA_DE_MI_CERTIFICADO=$HUELLA_SECRETO" "$D/03-respuesta.txt" || exit 1
grep -qxF "HUELLA_SERVIDA_POR_LA_ENTRADA=$HUELLA_SERVIDA" "$D/03-respuesta.txt" || exit 1
grep -qxF "CODIGO_HTTPS=$CODIGO" "$D/03-respuesta.txt" || exit 1
echo ok
