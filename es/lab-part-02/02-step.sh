#!/usr/bin/env bash
# lab-part-02 step 2 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

KC="$HOME/cks-lab/p02/kubeconfig"
K="kubectl --kubeconfig $KC"
BB="busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0"
cd ~/cks-lab/p02

$K -n porteria exec ronda-nocturna -- ls -1 /var/run/secrets/kubernetes.io/serviceaccount
$K -n porteria get serviceaccount celador-sin-llaves -o yaml | grep -i automount \
  || echo "(la cuenta no dice nada, y no decir nada es decir que si)"

$K -n porteria patch serviceaccount celador-sin-llaves \
  -p '{"automountServiceAccountToken": false}'

cat > ronda-nocturna.yaml <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: ronda-nocturna
  namespace: porteria
spec:
  serviceAccountName: celador-sin-llaves
  automountServiceAccountToken: false
  containers:
  - name: ronda
    image: $BB
    command: ["sh","-c","while true; do date -u +%Y-%m-%dT%H:%M:%SZ >> /tmp/ronda.log; sleep 3; done"]
    resources:
      requests: {cpu: 50m, memory: 32Mi}
      limits: {cpu: 200m, memory: 128Mi}
YAML

$K -n porteria delete pod ronda-nocturna --now
$K apply -f ronda-nocturna.yaml
$K -n porteria wait --for=condition=Ready pod/ronda-nocturna --timeout=180s

$K -n porteria exec ronda-nocturna -- sh -c \
  'ls /var/run/secrets/kubernetes.io/serviceaccount 2>&1 || echo "(no hay carpeta de token)"'
$K -n porteria get pod ronda-nocturna \
  -o jsonpath='cuenta={.spec.serviceAccountName}{"\n"}automount_del_pod={.spec.automountServiceAccountToken}{"\n"}'
$K -n porteria exec ronda-nocturna -- sh -c 'wc -l < /tmp/ronda.log'
sleep 8
$K -n porteria exec ronda-nocturna -- sh -c 'wc -l < /tmp/ronda.log; tail -2 /tmp/ronda.log'
# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/cks-lab/p02"
$K -n porteria exec ronda-nocturna -- ls /var/run/secrets/kubernetes.io/serviceaccount >/dev/null 2>&1 && CARPETA=EXISTE || CARPETA=NO_EXISTE
cat > "$D/02-respuesta.txt" <<RESP
AUTOMOUNT_EN_LA_CUENTA=$($K -n porteria get serviceaccount celador-sin-llaves -o jsonpath='{.automountServiceAccountToken}')
AUTOMOUNT_EN_EL_POD=$($K -n porteria get pod ronda-nocturna -o jsonpath='{.spec.automountServiceAccountToken}')
CARPETA_DEL_TOKEN=$CARPETA
CUENTA_DE_LA_RONDA=$($K -n porteria get pod ronda-nocturna -o jsonpath='{.spec.serviceAccountName}')
RESP
cat "$D/02-respuesta.txt"
