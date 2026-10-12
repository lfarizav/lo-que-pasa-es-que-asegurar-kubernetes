#!/usr/bin/env bash
# lab-part-03 step 2 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

KC="$HOME/cks-lab/p03/kubeconfig"
NODO="cks-p03-control-plane"
cd ~/cks-lab/p03

docker exec "$NODO" sh -c 'mkdir -p /var/lib/kubelet/seccomp/profiles && cat > /var/lib/kubelet/seccomp/profiles/candado-del-local.json <<JSON
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "architectures": ["SCMP_ARCH_X86_64","SCMP_ARCH_X86","SCMP_ARCH_X32"],
  "syscalls": [
    {"names": ["chmod","fchmod","fchmodat","fchmodat2"], "action": "SCMP_ACT_ERRNO", "errnoRet": 1}
  ]
}
JSON'
docker exec "$NODO" cat /var/lib/kubelet/seccomp/profiles/candado-del-local.json

cat > tienda-del-conjunto.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: tienda-del-conjunto
  namespace: conjunto
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/candado-del-local.json
  containers:
  - name: tendero
    image: busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0
    command: ["sh","-c","sleep 86400"]
YAML

kubectl --kubeconfig "$KC" apply -f tienda-del-conjunto.yaml
kubectl --kubeconfig "$KC" -n conjunto wait --for=condition=Ready pod/tienda-del-conjunto --timeout=180s

kubectl --kubeconfig "$KC" -n conjunto exec tienda-del-conjunto -- grep ^Seccomp: /proc/1/status
kubectl --kubeconfig "$KC" -n conjunto exec tienda-del-conjunto -- touch /tmp/inventario; echo "touch_rc=$?"
kubectl --kubeconfig "$KC" -n conjunto exec tienda-del-conjunto -- chmod 700 /tmp/inventario; echo "chmod_rc=$?"

kubectl --kubeconfig "$KC" -n conjunto get pod tienda-del-conjunto \
  -o jsonpath='ruta={.spec.securityContext.seccompProfile.localhostProfile}{"\n"}'

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/cks-lab/p03"
cat > "$D/02-respuesta.txt" <<RESP
RUTA_DEL_PERFIL=$(kubectl --kubeconfig "$KC" -n conjunto get pod tienda-del-conjunto -o jsonpath='{.spec.securityContext.seccompProfile.localhostProfile}')
ACCION_POR_DEFECTO=$(docker exec "$NODO" cat /var/lib/kubelet/seccomp/profiles/candado-del-local.json | jq -r .defaultAction)
RESP
cat "$D/02-respuesta.txt"
