#!/usr/bin/env bash
# lab-part-05 step 4 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

LAB="$HOME/cks-lab/p05"
K="kubectl --kubeconfig $LAB/kubeconfig --context kind-cks-p05"
ACEPTA='application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
cd "$LAB"

export COSIGN_PASSWORD=""
rm -f despacho.key despacho.pub
"$LAB/cosign" generate-key-pair --output-key-prefix "$LAB/despacho"
cat despacho.pub

DIG=$(curl -sI -H "Accept: $ACEPTA" http://127.0.0.1:5065/v2/tienda/proveedor-b/manifests/2026-08 \
      | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}')
echo "digest de la caja aprobada: $DIG"

"$LAB/cosign" sign --key "$LAB/despacho.key" --tlog-upload=false --allow-insecure-registry --yes \
  "127.0.0.1:5065/tienda/proveedor-b@$DIG"

"$LAB/cosign" verify --key "$LAB/despacho.pub" --insecure-ignore-tlog --allow-insecure-registry \
  "127.0.0.1:5065/tienda/proveedor-b@$DIG" >/dev/null && echo "la firmada verifica"
DIGA=$(curl -sI -H "Accept: $ACEPTA" http://127.0.0.1:5065/v2/tienda/proveedor-a/manifests/2026-08 \
      | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}')
"$LAB/cosign" verify --key "$LAB/despacho.pub" --insecure-ignore-tlog --allow-insecure-registry \
  "127.0.0.1:5065/tienda/proveedor-a@$DIGA" || echo "la sin firma NO verifica, que es lo correcto"

LLAVE=$(sed 's/^/              /' "$LAB/despacho.pub")
cat > "$LAB/04-exigir-sello.yaml" <<YAML
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: exigir-sello-del-despacho
spec:
  background: false
  webhookTimeoutSeconds: 30
  rules:
  - name: sin-sello-no-sube-a-la-vitrina
    match:
      any:
      - resources:
          kinds:
          - Pod
          namespaces:
          - el-deposito
    verifyImages:
    - imageReferences:
      - "cks-p05-registry:5000/tienda/*"
      failureAction: Enforce
      required: true
      mutateDigest: true
      verifyDigest: true
      attestors:
      - count: 1
        entries:
        - keys:
            publicKeys: |-
$LLAVE
            rekor:
              ignoreTlog: true
            ctlog:
              ignoreSCT: true
YAML
$K apply -f "$LAB/04-exigir-sello.yaml"
sleep 8

$K apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: el-aprobado
  namespace: el-deposito
spec:
  containers:
  - name: app
    image: cks-p05-registry:5000/tienda/proveedor-b:2026-08
    resources:
      limits:
        cpu: 100m
        memory: 64Mi
YAML
$K -n el-deposito get pod el-aprobado -o jsonpath='{.spec.containers[0].image}{"\n"}'

$K apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: el-rechazado
  namespace: el-deposito
spec:
  containers:
  - name: app
    image: cks-p05-registry:5000/tienda/proveedor-a:2026-08
    resources:
      limits:
        cpu: 100m
        memory: 64Mi
YAML

printf 'POLITICA_VERIFY=exigir-sello-del-despacho\nDIGEST_FIRMADO=%s\n' "$DIG" > "$LAB/04-respuesta.txt"
cat "$LAB/04-respuesta.txt"
