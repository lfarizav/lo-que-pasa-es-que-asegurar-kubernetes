#!/usr/bin/env bash
# lab-part-04 step 4 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

KC="$HOME/cks-lab/p04/kubeconfig"
cd ~/cks-lab/p04

kubectl --kubeconfig "$KC" -n citofono get configmap citofono-conf -o jsonpath='{.data.citofono\.conf}'

cat > citofono.conf <<'CONF'
server {
    listen 8443 ssl;
    server_name citofono;

    ssl_certificate        /etc/nginx/tls/tls.crt;
    ssl_certificate_key    /etc/nginx/tls/tls.key;
    ssl_client_certificate /etc/nginx/ca/ca.crt;
    ssl_verify_client      on;

    location / {
        default_type text/plain;
        return 200 "citofono del 303: adelante, $ssl_client_s_dn\n";
    }
}
CONF

kubectl --kubeconfig "$KC" -n citofono create configmap citofono-conf \
  --from-file=citofono.conf=citofono.conf --dry-run=client -o yaml \
  | kubectl --kubeconfig "$KC" replace -f -

kubectl --kubeconfig "$KC" -n citofono delete pod citofono --wait=true
kubectl --kubeconfig "$KC" apply -f citofono-pod.yaml
kubectl --kubeconfig "$KC" -n citofono wait --for=condition=Ready pod/citofono --timeout=180s
sleep 10

kubectl --kubeconfig "$KC" -n citofono exec vecino -- \
  curl -s -o /dev/null -w 'sin_carnet=%{http_code}\n' --cacert /carnet/ca.crt https://citofono:8443/
kubectl --kubeconfig "$KC" -n citofono exec vecino -- \
  curl -s -o /dev/null -w 'carnet_de_la_calle=%{http_code}\n' --cacert /carnet/ca.crt \
  --cert /calle/impostor.crt --key /calle/impostor.key https://citofono:8443/
kubectl --kubeconfig "$KC" -n citofono exec vecino -- \
  curl -s -o /dev/null -w 'carnet_del_vecino=%{http_code}\n' --cacert /carnet/ca.crt \
  --cert /carnet/vecino.crt --key /carnet/vecino.key https://citofono:8443/
kubectl --kubeconfig "$KC" -n citofono exec vecino -- \
  curl -sS --cacert /carnet/ca.crt --cert /carnet/vecino.crt --key /carnet/vecino.key https://citofono:8443/
# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/cks-lab/p04"
V="kubectl --kubeconfig $KC -n citofono exec vecino --"
cat > "$D/04-respuesta.txt" <<RESP
SIN_CARNET=$($V curl -s -o /dev/null -w '%{http_code}' --cacert /carnet/ca.crt https://citofono:8443/)
CARNET_DE_LA_CALLE=$($V curl -s -o /dev/null -w '%{http_code}' --cacert /carnet/ca.crt --cert /calle/impostor.crt --key /calle/impostor.key https://citofono:8443/)
CON_CARNET=$($V curl -s -o /dev/null -w '%{http_code}' --cacert /carnet/ca.crt --cert /carnet/vecino.crt --key /carnet/vecino.key https://citofono:8443/)
RESP
cat "$D/04-respuesta.txt"
