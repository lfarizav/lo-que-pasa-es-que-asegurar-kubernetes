#!/usr/bin/env bash
# lab-part-01 step 1 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/cks-lab/p01
K="kubectl --kubeconfig $HOME/cks-lab/p01/kubeconfig"
FQDN=citofono-301.la-torre-tres.svc.cluster.local
DESTINO=$($K -n la-torre-tres get pod el-apartamento-301 -o jsonpath='{.status.podIP}')
echo "el apartamento 301 vive en $DESTINO"

echo "--- LINEA BASE, sin ninguna politica ---"
$K -n la-torre-tres exec el-vecino-autorizado -- wget -q -T 5 -O- "http://$FQDN" >/dev/null 2>&1
echo "vecino por nombre antes: $?"
$K -n la-torre-tres exec el-desconocido-del-portal -- wget -q -T 5 -O- "http://$DESTINO" >/dev/null 2>&1
echo "desconocido por IP antes: $?"

cat > politicas-torre.yaml <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: negar-todo-en-la-torre
  namespace: la-torre-tres
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: dejar-entrar-al-vecino
  namespace: la-torre-tres
spec:
  podSelector:
    matchLabels:
      rol: apartamento
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          visita: autorizada
    ports:
    - protocol: TCP
      port: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: dejar-salir-al-vecino
  namespace: la-torre-tres
spec:
  podSelector:
    matchLabels:
      visita: autorizada
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          rol: apartamento
    ports:
    - protocol: TCP
      port: 80
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
YAML

$K apply -f politicas-torre.yaml
$K -n la-torre-tres get networkpolicies
sleep 10

echo "--- DESPUES DE PONER EL REGLAMENTO ---"
$K -n la-torre-tres exec el-vecino-autorizado -- wget -q -T 8 -O- "http://$FQDN" >/dev/null 2>&1
echo "vecino por nombre despues: $?"
$K -n la-torre-tres exec el-desconocido-del-portal -- wget -q -T 8 -O- "http://$DESTINO" >/dev/null 2>&1
echo "desconocido por IP despues: $?"

$K -n la-torre-tres get netpol -o jsonpath='{.items[*].metadata.name}{"\n"}'

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/cks-lab/p01"
$K -n la-torre-tres exec el-vecino-autorizado -- wget -q -T 8 -O- "http://$FQDN" >/dev/null 2>&1; SV=$?
$K -n la-torre-tres exec el-desconocido-del-portal -- wget -q -T 8 -O- "http://$DESTINO" >/dev/null 2>&1; SD=$?
cat > "$D/01-respuesta.txt" <<RESP
SALIDA_VECINO=$SV
SALIDA_DESCONOCIDO=$SD
POLITICAS_EN_LA_TORRE=$($K -n la-torre-tres get netpol -o jsonpath='{.items[*].metadata.name}' | wc -w)
RESP
cat "$D/01-respuesta.txt"
