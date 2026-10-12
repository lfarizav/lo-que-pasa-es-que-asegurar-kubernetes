#!/usr/bin/env bash
# lab-part-04 step 1 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

KC="$HOME/cks-lab/p04/kubeconfig"
BB="busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0"
cd ~/cks-lab/p04

kubectl --kubeconfig "$KC" get namespace torre-a --show-labels
kubectl --kubeconfig "$KC" apply -f inquilino.yaml

kubectl --kubeconfig "$KC" label namespace torre-a \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest --overwrite

kubectl --kubeconfig "$KC" apply -f inquilino.yaml

cat > inquilino.yaml <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: inquilino
  namespace: torre-a
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: inquilino
    image: $BB
    command: ["sh","-c","sleep 86400"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
YAML

kubectl --kubeconfig "$KC" apply -f inquilino.yaml
kubectl --kubeconfig "$KC" -n torre-a wait --for=condition=Ready pod/inquilino --timeout=180s
kubectl --kubeconfig "$KC" get namespace torre-a \
  -o jsonpath='nivel={.metadata.labels.pod-security\.kubernetes\.io/enforce}{"\n"}version={.metadata.labels.pod-security\.kubernetes\.io/enforce-version}{"\n"}'
kubectl --kubeconfig "$KC" -n torre-a exec inquilino -- id -u
# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/cks-lab/p04"
cat > "$D/01-respuesta.txt" <<RESP
NIVEL_APLICADO=$(kubectl --kubeconfig "$KC" get namespace torre-a -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')
USUARIO_DEL_INQUILINO=$(kubectl --kubeconfig "$KC" -n torre-a exec inquilino -- id -u)
RESP
cat "$D/01-respuesta.txt"
