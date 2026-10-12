#!/usr/bin/env bash
# lab-part-05 - setup
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

set -e
LAB="$HOME/cks-lab/p05"
mkdir -p "$LAB/la-tienda" "$LAB/suministros"
cd "$LAB"

KC="$LAB/kubeconfig"
K="kubectl --kubeconfig $KC --context kind-cks-p05"
REG=127.0.0.1:5065
CREG=cks-p05-registry:5000
ACEPTA='application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
NODO=kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5
REGIMG=registry:3@sha256:1be55279f18a2fe1a74edf2664cac61c1bea305b7b4642dab412e7affdcb3e33
GORDA=golang:1.25@sha256:fe5d57d3b718e7a4986bae156c2d73f44973bfd313073aed08a4de6692bb6161
ALPINA=alpine:3.22@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce

for herramienta in docker kind kubectl helm jq curl; do
  command -v "$herramienta" >/dev/null 2>&1 || { echo "FALTA: $herramienta - instalelo antes de continuar."; exit 1; }
done
kind version
kubectl version --client=true 2>/dev/null | head -1
docker version -f '{{.Server.Version}}'
helm version --short

# Herramientas fijadas por version, dentro del espacio de trabajo, para que lo que
# usted use y lo que la comprobacion use sean exactamente el mismo binario.
if [ ! -x "$LAB/cosign" ]; then
  curl -sSLf -o "$LAB/cosign" https://github.com/sigstore/cosign/releases/download/v2.6.5/cosign-linux-amd64
  chmod +x "$LAB/cosign"
fi
"$LAB/cosign" version 2>&1 | grep GitVersion
if [ ! -x "$LAB/trivy" ]; then
  curl -sSLf -o "$LAB/trivy.tgz" https://github.com/aquasecurity/trivy/releases/download/v0.74.0/trivy_0.74.0_Linux-64bit.tar.gz
  tar xzf "$LAB/trivy.tgz" -C "$LAB" trivy
  rm -f "$LAB/trivy.tgz"
fi
"$LAB/trivy" --version | head -1

# El cluster primero, porque es quien crea la red docker llamada kind.
# El config_path le dice al containerd del nodo que lea /etc/containerd/certs.d,
# que es la forma soportada de declarar un registro que habla HTTP.
cat > "$LAB/kind-cks-p05.yaml" <<'KINDCFG'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: cks-p05
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"
KINDCFG
kind create cluster --config "$LAB/kind-cks-p05.yaml" --kubeconfig "$KC" --image "$NODO"
$K wait --for=condition=Ready nodes --all --timeout=180s

# Registro local propio: nombre unico y puerto unico. Se publica en 127.0.0.1
# porque docker ya trata 127.0.0.0/8 como registro inseguro y el push va sobre HTTP.
docker rm -f cks-p05-registry >/dev/null 2>&1 || true
docker run -d --restart=always -p 127.0.0.1:5065:5000 --name cks-p05-registry "$REGIMG" >/dev/null
docker network connect kind cks-p05-registry >/dev/null 2>&1 || true
for i in 1 2 3 4 5 6 7 8 9 10; do
  curl -sf http://$REG/v2/ >/dev/null 2>&1 && break
  sleep 1
done
curl -sf http://$REG/v2/ >/dev/null || { echo "ERROR DE SUSTRATO: REGISTRO-NO-RESPONDE en $REG."; exit 1; }

# El containerd del nodo habla HTTPS por defecto. Esta es la forma soportada de
# decirle que este registro de laboratorio habla HTTP.
docker exec cks-p05-control-plane mkdir -p "/etc/containerd/certs.d/$CREG"
docker exec cks-p05-control-plane sh -c "cat > /etc/containerd/certs.d/$CREG/hosts.toml <<EOF
server = \"http://$CREG\"
[host.\"http://$CREG\"]
  capabilities = [\"pull\", \"resolve\"]
EOF"

# La tienda: un servidor HTTP diminuto en Go, y el Dockerfile inflado del Paso 1.
cat > "$LAB/la-tienda/tienda.go" <<'GO'
package main

import (
	"fmt"
	"net/http"
	"runtime"
)

const carta = "pan-de-la-esquina-v1"

func main() {
	http.HandleFunc("/version", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, runtime.Version())
	})
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, carta)
	})
	http.ListenAndServe(":8080", nil)
}
GO
cat > "$LAB/la-tienda/Dockerfile.bodega" <<DOCKER
FROM $GORDA
WORKDIR /src
COPY tienda.go .
RUN go mod init tienda
ENV CGO_ENABLED=0
RUN go build -o /tienda ./tienda.go
EXPOSE 8080
CMD ["/tienda"]
DOCKER
docker build -q -t la-tienda:bodega -f "$LAB/la-tienda/Dockerfile.bodega" "$LAB/la-tienda" >/dev/null
echo "imagen inflada la-tienda:bodega construida, $(docker image inspect la-tienda:bodega -f '{{.Size}}') bytes"

# La imagen que el Paso 2 va a repintar por digest.
cat > "$LAB/la-tienda/Dockerfile.vitrina" <<DOCKER
FROM $GORDA AS constructor
WORKDIR /src
COPY tienda.go .
RUN go mod init tienda
ENV CGO_ENABLED=0
RUN go build -o /tienda ./tienda.go

FROM $ALPINA
COPY --from=constructor /tienda /tienda
EXPOSE 8080
CMD ["/tienda"]
DOCKER
docker build -q -t $REG/tienda/pan:v1 -f "$LAB/la-tienda/Dockerfile.vitrina" "$LAB/la-tienda" >/dev/null
docker push -q $REG/tienda/pan:v1

# Los dos proveedores del Paso 3. Cada caja trae adentro una libreria de registro
# de eventos; una de las dos viene de un lote viejo. Cual es cual lo dice trivy.
cd "$LAB/suministros"
curl -sSLf -o log4j-core-2.14.1.jar https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-core/2.14.1/log4j-core-2.14.1.jar \
  || { echo "ERROR DE SUSTRATO: SIN-SUMINISTROS. No se pudo bajar el .jar desde repo1.maven.org."; exit 1; }
curl -sSLf -o log4j-core-2.17.1.jar https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-core/2.17.1/log4j-core-2.17.1.jar \
  || { echo "ERROR DE SUSTRATO: SIN-SUMINISTROS. No se pudo bajar el .jar desde repo1.maven.org."; exit 1; }
echo "ade7402a70667a727635d5c4c29495f4ff96f061f12539763f6f123973b465b0  log4j-core-2.14.1.jar" | sha256sum -c -
echo "c967f223487980b9364e94a7c7f9a8a01fd3ee7c19bdbf0b0f9f8cb8511f3d41  log4j-core-2.17.1.jar" | sha256sum -c -
cat > Dockerfile.a <<DOCKER
FROM $ALPINA
LABEL org.tienda.deposito="el-del-centro"
RUN mkdir -p /opt/despacho/lib
COPY log4j-core-2.14.1.jar /opt/despacho/lib/log4j-core-2.14.1.jar
CMD ["sh","-c","echo deposito-del-centro; sleep infinity"]
DOCKER
cat > Dockerfile.b <<DOCKER
FROM $ALPINA
LABEL org.tienda.deposito="el-del-barrio"
RUN mkdir -p /opt/despacho/lib
COPY log4j-core-2.17.1.jar /opt/despacho/lib/log4j-core-2.17.1.jar
CMD ["sh","-c","echo deposito-del-barrio; sleep infinity"]
DOCKER
docker build -q -f Dockerfile.a -t $REG/tienda/proveedor-a:2026-08 . >/dev/null
docker build -q -f Dockerfile.b -t $REG/tienda/proveedor-b:2026-08 . >/dev/null
docker push -q $REG/tienda/proveedor-a:2026-08
docker push -q $REG/tienda/proveedor-b:2026-08
cd "$LAB"

echo "PRUEBA DE SUSTRATO 1 de 3: el nodo puede traer una imagen del registro local por HTTP"
$K create namespace prueba-de-sustrato >/dev/null
$K -n prueba-de-sustrato run trae-la-caja --restart=Never --image="$CREG/tienda/proveedor-b:2026-08" --command -- sh -c 'exit 0' >/dev/null
if ! $K -n prueba-de-sustrato wait --for=jsonpath='{.status.phase}'=Succeeded pod/trae-la-caja --timeout=240s >/dev/null; then
  echo "ERROR DE SUSTRATO: NODO-NO-BAJA-DEL-REGISTRO."
  echo "El containerd del nodo no pudo traer $CREG/tienda/proveedor-b:2026-08 por HTTP."
  echo "Los Pasos 2, 3 y 4 son decoracion hasta que eso funcione."
  $K -n prueba-de-sustrato describe pod trae-la-caja | tail -20
  exit 1
fi
$K -n prueba-de-sustrato delete pod trae-la-caja --wait=true >/dev/null

echo "PRUEBA DE SUSTRATO 2 de 3: trivy distingue de verdad las dos cajas"
export TRIVY_CACHE_DIR="$LAB/trivy-cache"
"$LAB/trivy" image --download-db-only --quiet >/dev/null 2>&1 || true
CRIT_A=$("$LAB/trivy" image --scanners vuln --severity CRITICAL --format json --quiet -o "$LAB/.sustrato-a.json" $REG/tienda/proveedor-a:2026-08 >/dev/null 2>&1; jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$LAB/.sustrato-a.json")
CRIT_B=$("$LAB/trivy" image --scanners vuln --severity CRITICAL --format json --quiet -o "$LAB/.sustrato-b.json" $REG/tienda/proveedor-b:2026-08 >/dev/null 2>&1; jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$LAB/.sustrato-b.json")
rm -f "$LAB/.sustrato-a.json" "$LAB/.sustrato-b.json"
echo "criticas en proveedor-a: $CRIT_A / criticas en proveedor-b: $CRIT_B"
if [ "$CRIT_A" -lt 1 ] || [ "$CRIT_B" -ne 0 ]; then
  echo "ERROR DE SUSTRATO: TRIVY-NO-SEPARA-LAS-CAJAS."
  echo "Se esperaba al menos una CRITICAL en una caja y cero en la otra."
  echo "La base de datos de trivy cambio de criterio y el Paso 3 no se puede calificar asi."
  exit 1
fi

# Kyverno, que es quien va a revisar el sello en la puerta en el Paso 4.
helm --kubeconfig "$KC" --kube-context kind-cks-p05 repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm --kubeconfig "$KC" --kube-context kind-cks-p05 repo update kyverno >/dev/null
helm --kubeconfig "$KC" --kube-context kind-cks-p05 install kyverno kyverno/kyverno \
  --version 3.9.0 -n kyverno --create-namespace \
  --set features.registryClient.allowInsecure=true --wait --timeout 10m >/dev/null
$K -n kyverno get pods --no-headers | awk '{print $1, $3}'

echo "PRUEBA DE SUSTRATO 3 de 3: la verificacion de firmas de verdad BLOQUEA"
$K -n prueba-de-sustrato run sin-politica --restart=Never --image="$CREG/tienda/proveedor-b:2026-08" --command -- sh -c 'exit 0' >/dev/null \
  || { echo "ERROR DE SUSTRATO: LINEA-BASE-ROTA. Ni siquiera sin politica se pudo crear el Pod."; exit 1; }
$K -n prueba-de-sustrato delete pod sin-politica --wait=true >/dev/null
export COSIGN_PASSWORD=""
rm -f "$LAB/.sustrato.key" "$LAB/.sustrato.pub"
"$LAB/cosign" generate-key-pair --output-key-prefix "$LAB/.sustrato" >/dev/null
LLAVE_SUSTRATO=$(sed 's/^/              /' "$LAB/.sustrato.pub")
cat > "$LAB/.sustrato-politica.yaml" <<YAML
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: prueba-de-sustrato-sello
spec:
  background: false
  webhookTimeoutSeconds: 30
  rules:
  - name: nadie-sin-sello
    match:
      any:
      - resources:
          kinds:
          - Pod
          namespaces:
          - prueba-de-sustrato
    verifyImages:
    - imageReferences:
      - "$CREG/tienda/*"
      failureAction: Enforce
      required: true
      mutateDigest: true
      verifyDigest: true
      attestors:
      - count: 1
        entries:
        - keys:
            publicKeys: |-
$LLAVE_SUSTRATO
            rekor:
              ignoreTlog: true
            ctlog:
              ignoreSCT: true
YAML
$K apply -f "$LAB/.sustrato-politica.yaml" >/dev/null
sleep 8
if $K -n prueba-de-sustrato run con-politica --restart=Never --image="$CREG/tienda/proveedor-b:2026-08" --command -- sh -c 'exit 0' >/dev/null 2>&1; then
  echo "ERROR DE SUSTRATO: SIN-VERIFICACION-DE-FIRMAS."
  echo "Kyverno acepto un Pod cuya imagen no tiene ninguna firma de esa llave."
  echo "El Paso 4 seria decoracion: el webhook no esta bloqueando nada."
  $K -n prueba-de-sustrato delete pod con-politica --ignore-not-found --wait=false >/dev/null 2>&1
  $K delete clusterpolicy prueba-de-sustrato-sello >/dev/null 2>&1
  exit 1
fi
echo "la verificacion de firmas bloquea: prueba de sustrato superada"
$K delete clusterpolicy prueba-de-sustrato-sello >/dev/null
$K delete namespace prueba-de-sustrato --wait=false >/dev/null
rm -f "$LAB/.sustrato.key" "$LAB/.sustrato.pub" "$LAB/.sustrato-politica.yaml"

# Los tres locales del laboratorio, y la vitrina pedida por apodo.
for LOCAL in la-vitrina la-bodega el-deposito; do
  $K create namespace "$LOCAL" >/dev/null
done
$K apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: la-vitrina
  namespace: la-vitrina
spec:
  replicas: 2
  selector:
    matchLabels:
      app: la-vitrina
  template:
    metadata:
      labels:
        app: la-vitrina
    spec:
      containers:
      - name: tienda
        image: $CREG/tienda/pan:v1
        ports:
        - containerPort: 8080
        resources:
          limits:
            cpu: 100m
            memory: 64Mi
YAML
$K -n la-vitrina rollout status deployment/la-vitrina --timeout=180s

kubectl config get-contexts

echo "espacio de trabajo listo en ~/cks-lab/p05"
echo "si la linea de arriba menciona cks-p05, el aislamiento fallo: revise el --kubeconfig"
