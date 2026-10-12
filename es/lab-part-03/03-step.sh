#!/usr/bin/env bash
# lab-part-03 step 3 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

KC="$HOME/cks-lab/p03/kubeconfig"
NODO="cks-p03-control-plane"
cd ~/cks-lab/p03

docker exec "$NODO" sh -c 'mkdir -p /etc/apparmor.d/cks && cat > /etc/apparmor.d/cks/bodega <<PERFIL
#include <tunables/global>

profile cks-p03-bodega-sin-lapicero flags=(attach_disconnected) {
  #include <abstractions/base>

  file,

  deny /** w,
}
PERFIL
apparmor_parser -q -r /etc/apparmor.d/cks/bodega'

docker exec "$NODO" grep cks-p03 /sys/kernel/security/apparmor/profiles

cat > bodega.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: bodega
  namespace: conjunto
spec:
  containers:
  - name: bodeguero
    image: busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0
    command: ["sh","-c","sleep 86400"]
    securityContext:
      appArmorProfile:
        type: Localhost
        localhostProfile: cks-p03-bodega-sin-lapicero
YAML

kubectl --kubeconfig "$KC" apply -f bodega.yaml
kubectl --kubeconfig "$KC" -n conjunto wait --for=condition=Ready pod/bodega --timeout=180s

kubectl --kubeconfig "$KC" -n conjunto exec bodega -- cat /proc/1/attr/current
kubectl --kubeconfig "$KC" -n conjunto exec bodega -- cat /etc/hostname; echo "lectura_rc=$?"
kubectl --kubeconfig "$KC" -n conjunto exec bodega -- touch /tmp/remision; echo "escritura_rc=$?"

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/cks-lab/p03"
cat > "$D/03-respuesta.txt" <<RESP
PERFIL_DEL_PROCESO=$(kubectl --kubeconfig "$KC" -n conjunto exec bodega -- cat /proc/1/attr/current | tr -d '\0')
MODO_EN_EL_NODO=$(docker exec "$NODO" grep '^cks-p03-bodega-sin-lapicero ' /sys/kernel/security/apparmor/profiles | grep -oE '\(([a-z]+)\)' | tr -d '()')
RESP
cat "$D/03-respuesta.txt"
