#!/usr/bin/env bash
# lab-part-04 step 3 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

KC="$HOME/cks-lab/p04/kubeconfig"
BB="busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0"
cd ~/cks-lab/p04

cat > empleado.yaml <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: empleado
  namespace: apartamento-303
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
  - name: empleado
    image: $BB
    command: ["sh","-c","while true; do date > /tmp/turno.txt; sleep 2; done"]
    securityContext:
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
    volumeMounts:
    - name: temporal
      mountPath: /tmp
  volumes:
  - name: temporal
    emptyDir: {}
YAML

kubectl --kubeconfig "$KC" apply -f empleado.yaml
kubectl --kubeconfig "$KC" -n apartamento-303 wait --for=condition=Ready pod/empleado --timeout=180s

kubectl --kubeconfig "$KC" -n apartamento-303 exec empleado -- id -u
kubectl --kubeconfig "$KC" -n apartamento-303 exec empleado -- grep ^CapEff /proc/1/status
kubectl --kubeconfig "$KC" -n apartamento-303 exec empleado -- sh -c 'touch /prueba-en-la-raiz' ; echo "salida=$?"
kubectl --kubeconfig "$KC" -n apartamento-303 exec empleado -- sh -c 'grep -E " / | /tmp " /proc/mounts'
kubectl --kubeconfig "$KC" -n apartamento-303 exec empleado -- cat /tmp/turno.txt
sleep 5
kubectl --kubeconfig "$KC" -n apartamento-303 exec empleado -- cat /tmp/turno.txt
# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/cks-lab/p04"
kubectl --kubeconfig "$KC" -n apartamento-303 exec empleado -- sh -c 'touch /prueba-en-la-raiz' 2>/dev/null && ESC=permitida || ESC=denegada
cat > "$D/03-respuesta.txt" <<RESP
UID_DEL_PROCESO=$(kubectl --kubeconfig "$KC" -n apartamento-303 exec empleado -- id -u)
CAPEFF_DEL_PROCESO=$(kubectl --kubeconfig "$KC" -n apartamento-303 exec empleado -- grep ^CapEff /proc/1/status | awk '{print $2}')
ESCRITURA_EN_LA_RAIZ=$ESC
RESP
cat "$D/03-respuesta.txt"
