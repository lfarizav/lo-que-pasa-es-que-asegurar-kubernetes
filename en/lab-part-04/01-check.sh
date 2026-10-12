#!/usr/bin/env bash
# lab-part-04 step 1 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
KC="$HOME/cks-lab/p04/kubeconfig"
D="$HOME/cks-lab/p04"
BB="busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0"
test -f "$D/01-respuesta.txt" || exit 1

NIVEL=$(kubectl --kubeconfig "$KC" get namespace torre-a -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)
test "$NIVEL" = "restricted" || exit 1
VERSION=$(kubectl --kubeconfig "$KC" get namespace torre-a -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce-version}' 2>/dev/null)
test -n "$VERSION" || exit 1

FASE=$(kubectl --kubeconfig "$KC" -n torre-a get pod inquilino -o jsonpath='{.status.phase}' 2>/dev/null)
test "$FASE" = "Running" || exit 1
LISTO=$(kubectl --kubeconfig "$KC" -n torre-a get pod inquilino -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
test "$LISTO" = "True" || exit 1
PRIV=$(kubectl --kubeconfig "$KC" -n torre-a get pod inquilino -o jsonpath='{.spec.containers[0].securityContext.privileged}' 2>/dev/null)
test "$PRIV" != "true" || exit 1

UID_VIVO=$(kubectl --kubeconfig "$KC" -n torre-a exec inquilino -- id -u 2>/dev/null | tr -d '\r')
echo "$UID_VIVO" | grep -qE '^[0-9]+$' || exit 1
test "$UID_VIVO" != "0" || exit 1

SALIDA1=$(kubectl --kubeconfig "$KC" -n torre-a run sonda-de-calificacion-1 \
  --image="$BB" --restart=Never --command -- sleep 60 2>&1)
kubectl --kubeconfig "$KC" -n torre-a delete pod sonda-de-calificacion-1 --ignore-not-found --wait=false >/dev/null 2>&1
echo "$SALIDA1" | grep -q 'violates PodSecurity "restricted' || exit 1

SALIDA2=$(kubectl --kubeconfig "$KC" apply -f - 2>&1 <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: sonda-de-calificacion-2
  namespace: torre-a
spec:
  containers:
  - name: c
    image: $BB
    command: ["sh","-c","sleep 60"]
    securityContext:
      privileged: true
YAML
)
kubectl --kubeconfig "$KC" -n torre-a delete pod sonda-de-calificacion-2 --ignore-not-found --wait=false >/dev/null 2>&1
echo "$SALIDA2" | grep -q "violates PodSecurity" || exit 1

grep -qxF "NIVEL_APLICADO=restricted" "$D/01-respuesta.txt" || exit 1
grep -qxF "USUARIO_DEL_INQUILINO=$UID_VIVO" "$D/01-respuesta.txt" || exit 1
echo ok
