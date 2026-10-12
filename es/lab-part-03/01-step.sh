#!/usr/bin/env bash
# lab-part-03 step 1 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

KC="$HOME/cks-lab/p03/kubeconfig"
cd ~/cks-lab/p03

kubectl --kubeconfig "$KC" -n conjunto get pod celaduria-sin-uniforme \
  -o jsonpath='gemelo={.spec.securityContext.seccompProfile.type}{"\n"}'

cat > celaduria-con-uniforme.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: celaduria-con-uniforme
  namespace: conjunto
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: celador
    image: busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0
    command: ["sh","-c","sleep 86400"]
YAML

kubectl --kubeconfig "$KC" apply -f celaduria-con-uniforme.yaml
kubectl --kubeconfig "$KC" -n conjunto wait --for=condition=Ready pod/celaduria-con-uniforme --timeout=180s

kubectl --kubeconfig "$KC" -n conjunto exec celaduria-con-uniforme -- grep ^Seccomp: /proc/1/status
kubectl --kubeconfig "$KC" -n conjunto exec celaduria-sin-uniforme -- grep ^Seccomp: /proc/1/status

kubectl --kubeconfig "$KC" -n conjunto exec celaduria-sin-uniforme -- unshare -U true; echo "gemelo_unshare_rc=$?"
kubectl --kubeconfig "$KC" -n conjunto exec celaduria-con-uniforme -- unshare -U true; echo "uniforme_unshare_rc=$?"

kubectl --kubeconfig "$KC" -n conjunto exec celaduria-con-uniforme -- unshare -m true
kubectl --kubeconfig "$KC" -n conjunto exec celaduria-sin-uniforme -- unshare -m true

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/cks-lab/p03"
K="kubectl --kubeconfig $KC"
cat > "$D/01-respuesta.txt" <<RESP
MODO_SECCOMP_CON_UNIFORME=$($K -n conjunto exec celaduria-con-uniforme -- grep ^Seccomp: /proc/1/status | awk '{print $2}')
MODO_SECCOMP_SIN_UNIFORME=$($K -n conjunto exec celaduria-sin-uniforme -- grep ^Seccomp: /proc/1/status | awk '{print $2}')
LLAMADA_BLOQUEADA=$($K -n conjunto exec celaduria-con-uniforme -- unshare -U true 2>&1 | grep -oE '0x[0-9a-fA-F]+' | head -1)
RESP
cat "$D/01-respuesta.txt"
