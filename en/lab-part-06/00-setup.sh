#!/usr/bin/env bash
# lab-part-06 - setup
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

set -e
W="$HOME/cks-lab/p06"
KC="$W/kubeconfig"
K="kubectl --kubeconfig $KC"
NODO="kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5"
BUSY="busybox@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0"
CURL="curlimages/curl@sha256:d94d07ba9e7d6de898b6d96c1a072f6f8266c687af78a74f380087a0addf5d17"
FALCO="falcosecurity/falco@sha256:d0cfe422d6ac0e0f20857798f46c7d7273210e1b064b22821e4e6e7f843cde6b"

for t in kind kubectl docker base64 jq script; do
  command -v "$t" >/dev/null 2>&1 || { echo "FALTA: $t - instalelo antes de empezar."; exit 1; }
done

mkdir -p "$W/auditoria" "$W/bin" "$W/local"

# ---------------------------------------------------------------- politica de auditoria
cat > "$W/auditoria/policy.yaml" <<'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
- "RequestReceived"
rules:
- level: None
  users: ["system:apiserver", "system:kube-scheduler", "system:kube-controller-manager", "system:kube-proxy"]
- level: None
  userGroups: ["system:nodes"]
- level: None
  nonResourceURLs: ["/healthz*", "/readyz*", "/livez*", "/version", "/metrics", "/openapi*", "/api*"]
- level: RequestResponse
  resources:
  - group: ""
    resources: ["secrets"]
- level: Metadata
EOF

cat > "$W/kind.yaml" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: cks-p06
nodes:
- role: control-plane
  image: $NODO
  extraMounts:
  - hostPath: $W/auditoria
    containerPath: /etc/kubernetes/audit
    readOnly: true
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    apiServer:
      extraArgs:
      - name: audit-policy-file
        value: /etc/kubernetes/audit/policy.yaml
      - name: audit-log-path
        value: /var/log/kubernetes/audit/audit.log
      - name: audit-log-maxage
        value: "7"
      - name: audit-log-maxbackup
        value: "2"
      - name: audit-log-maxsize
        value: "200"
      extraVolumes:
      - name: audit-policy
        hostPath: /etc/kubernetes/audit/policy.yaml
        mountPath: /etc/kubernetes/audit/policy.yaml
        readOnly: true
        pathType: File
      - name: audit-log
        hostPath: /var/log/kubernetes/audit
        mountPath: /var/log/kubernetes/audit
        readOnly: false
        pathType: DirectoryOrCreate
EOF

kind delete cluster --name cks-p06 --kubeconfig "$KC" >/dev/null 2>&1 || true
kind create cluster --config "$W/kind.yaml" --kubeconfig "$KC" --wait 300s
chmod 600 "$KC"
$K wait --for=condition=Ready nodes --all --timeout=300s >/dev/null

cat > "$W/bin/minuta" <<'EOF'
#!/bin/sh
exec docker exec cks-p06-control-plane cat /var/log/kubernetes/audit/audit.log
EOF
cat > "$W/bin/camaras" <<'EOF'
#!/bin/sh
exec docker exec cks-p06-control-plane sh -c 'cat /var/log/falco/events.txt 2>/dev/null'
EOF
chmod +x "$W/bin/minuta" "$W/bin/camaras"

# ---------------------------------------------------- SONDA 1: la minuta escribe de verdad
$K create namespace la-porteria >/dev/null
$K -n la-porteria create secret generic sonda-de-montaje --from-literal=x=y >/dev/null
sleep 3
if ! "$W/bin/minuta" | grep -q 'sonda-de-montaje'; then
  echo "ERROR SONDA-MINUTA-MUDA: el API server no esta escribiendo la bitacora de auditoria."
  echo "Sin bitacora, los Pasos 1, 2 y 4 de este laboratorio serian decoracion. El montaje se detiene."
  exit 1
fi
NIVEL_SEC=$("$W/bin/minuta" | jq -r 'select(.objectRef.name=="sonda-de-montaje" and .verb=="create") | .level' | head -1)
if [ "$NIVEL_SEC" != "RequestResponse" ]; then
  echo "ERROR SONDA-NIVEL-SECRETOS: la politica no esta aplicando RequestResponse a los Secrets (vi: $NIVEL_SEC)."
  echo "El Paso 2 depende de que el cuerpo del Secret quede escrito en la bitacora. El montaje se detiene."
  exit 1
fi
$K -n la-porteria delete secret sonda-de-montaje >/dev/null
echo "sonda-minuta: la bitacora de auditoria escribe, y los Secrets quedan en nivel RequestResponse."

# ------------------------------------------------------------- Paso 2: el incidente opaco
# La secuencia del incidente llega codificada en base64 A PROPOSITO. Eso no es
# criptografia y no pretende serlo: es una venda de cortesia, para que usted no
# lea en el mismo script lo que tiene que reconstruir desde la bitacora. El
# incidente es identico para todo el mundo en todas las corridas, y la respuesta
# completa esta en el campo cmd del Paso 2.
printf '%s' 'c2V0IC1lCks9Imt1YmVjdGwgLS1rdWJlY29uZmlnICRLQyIKCiRLIGNyZWF0ZSBuYW1lc3BhY2UgbGEtYm9kZWdhID4vZGV2L251bGwKJEsgLW4gbGEtYm9kZWdhIGNyZWF0ZSBzZWNyZXQgZ2VuZXJpYyBsYS1jYWphLWZ1ZXJ0ZSBcCiAgLS1mcm9tLWxpdGVyYWw9Y2xhdmU9Y29tYmluYWNpb24tNzQzMS1kZS1sYS1jYWphLWZ1ZXJ0ZSA+L2Rldi9udWxsCiRLIC1uIGxhLWJvZGVnYSBjcmVhdGUgY29uZmlnbWFwIGludmVudGFyaW8gLS1mcm9tLWxpdGVyYWw9Y2FqYXM9NDIgPi9kZXYvbnVsbAokSyAtbiBsYS1ib2RlZ2EgY3JlYXRlIHNlcnZpY2VhY2NvdW50IGF1eGlsaWFyLWRlLWRpYSA+L2Rldi9udWxsCiRLIC1uIGxhLWJvZGVnYSBjcmVhdGUgcm9sZSBsZWN0dXJhLWRlLWludmVudGFyaW8gXAogIC0tdmVyYj1nZXQsbGlzdCAtLXJlc291cmNlPWNvbmZpZ21hcHMgPi9kZXYvbnVsbAokSyAtbiBsYS1ib2RlZ2EgY3JlYXRlIHJvbGViaW5kaW5nIHR1cm5vLWRlLWRpYSBcCiAgLS1yb2xlPWxlY3R1cmEtZGUtaW52ZW50YXJpbyAtLXNlcnZpY2VhY2NvdW50PWxhLWJvZGVnYTphdXhpbGlhci1kZS1kaWEgPi9kZXYvbnVsbAoKU0VSVkVSPSQoJEsgY29uZmlnIHZpZXcgLS1taW5pZnkgLW8ganNvbnBhdGg9J3suY2x1c3RlcnNbMF0uY2x1c3Rlci5zZXJ2ZXJ9JykKQ0E9JCgkSyBjb25maWcgdmlldyAtLW1pbmlmeSAtLXJhdyAtbyBqc29ucGF0aD0ney5jbHVzdGVyc1swXS5jbHVzdGVyLmNlcnRpZmljYXRlLWF1dGhvcml0eS1kYXRhfScpCgprY19wYXJhKCkgewogIGNhdCA+ICIkVy8ua2MtJDEiIDw8RU9GMgphcGlWZXJzaW9uOiB2MQpraW5kOiBDb25maWcKY2x1c3RlcnM6Ci0gbmFtZTogYwogIGNsdXN0ZXI6CiAgICBzZXJ2ZXI6ICRTRVJWRVIKICAgIGNlcnRpZmljYXRlLWF1dGhvcml0eS1kYXRhOiAkQ0EKY29udGV4dHM6Ci0gbmFtZTogYwogIGNvbnRleHQ6IHtjbHVzdGVyOiBjLCB1c2VyOiB1LCBuYW1lc3BhY2U6IGxhLWJvZGVnYX0KY3VycmVudC1jb250ZXh0OiBjCnVzZXJzOgotIG5hbWU6IHUKICB1c2VyOgogICAgdG9rZW46ICQyCkVPRjIKICBjaG1vZCA2MDAgIiRXLy5rYy0kMSIKfQoKVE9LX0RJQT0kKCRLIC1uIGxhLWJvZGVnYSBjcmVhdGUgdG9rZW4gYXV4aWxpYXItZGUtZGlhIC0tZHVyYXRpb249MzYwMHMpCmtjX3BhcmEgZGlhICIkVE9LX0RJQSIKa3ViZWN0bCAtLWt1YmVjb25maWcgIiRXLy5rYy1kaWEiIC1uIGxhLWJvZGVnYSBnZXQgY29uZmlnbWFwIGludmVudGFyaW8gPi9kZXYvbnVsbCAyPiYxIHx8IHRydWUKCiRLIC1uIGxhLWJvZGVnYSBjcmVhdGUgc2VydmljZWFjY291bnQgYXV4aWxpYXItZGUtdHVybm8gPi9kZXYvbnVsbApUT0tfTk9DPSQoJEsgLW4gbGEtYm9kZWdhIGNyZWF0ZSB0b2tlbiBhdXhpbGlhci1kZS10dXJubyAtLWR1cmF0aW9uPTM2MDBzKQprY19wYXJhIG5vY2hlICIkVE9LX05PQyIKa3ViZWN0bCAtLWt1YmVjb25maWcgIiRXLy5rYy1ub2NoZSIgLW4gbGEtYm9kZWdhIGdldCBwb2RzID4vZGV2L251bGwgMj4mMSB8fCB0cnVlCmt1YmVjdGwgLS1rdWJlY29uZmlnICIkVy8ua2Mtbm9jaGUiIC1uIGxhLWJvZGVnYSBnZXQgc2VjcmV0IGxhLWNhamEtZnVlcnRlID4vZGV2L251bGwgMj4mMSB8fCB0cnVlCgokSyAtbiBsYS1ib2RlZ2EgY3JlYXRlIHJvbGUgbGxhdmVzLWRlLWxhLWNhamEgXAogIC0tdmVyYj1nZXQgLS1yZXNvdXJjZT1zZWNyZXRzID4vZGV2L251bGwKJEsgLW4gbGEtYm9kZWdhIGNyZWF0ZSByb2xlYmluZGluZyBwcmVzdGFtby1kZS1sbGF2ZXMgXAogIC0tcm9sZT1sbGF2ZXMtZGUtbGEtY2FqYSAtLXNlcnZpY2VhY2NvdW50PWxhLWJvZGVnYTphdXhpbGlhci1kZS10dXJubyA+L2Rldi9udWxsCnNsZWVwIDMKa3ViZWN0bCAtLWt1YmVjb25maWcgIiRXLy5rYy1ub2NoZSIgLW4gbGEtYm9kZWdhIGdldCBzZWNyZXQgbGEtY2FqYS1mdWVydGUgLW8geWFtbCA+L2Rldi9udWxsCmt1YmVjdGwgLS1rdWJlY29uZmlnICIkVy8ua2MtZGlhIiAtbiBsYS1ib2RlZ2EgZ2V0IGNvbmZpZ21hcCBpbnZlbnRhcmlvID4vZGV2L251bGwgMj4mMSB8fCB0cnVlCgpybSAtZiAiJFcvLmtjLWRpYSIgIiRXLy5rYy1ub2NoZSIK' | base64 -d > "$W/.incidente.sh"
KC="$KC" W="$W" sh "$W/.incidente.sh"
rm -f "$W/.incidente.sh"

# ------------------------------------------------------------------ Paso 3: las camaras
$K create namespace la-celaduria >/dev/null
cat > "$W/falco.yaml" <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: falco
  namespace: la-celaduria
spec:
  selector:
    matchLabels:
      app: falco
  template:
    metadata:
      labels:
        app: falco
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: falco
        image: $FALCO
        args:
        - /usr/bin/falco
        - -o
        - engine.kind=modern_ebpf
        - -o
        - json_output=true
        - -o
        - file_output.enabled=true
        - -o
        - file_output.keep_alive=false
        - -o
        - file_output.filename=/var/log/falco/events.txt
        securityContext:
          privileged: true
        volumeMounts:
        - name: proc
          mountPath: /host/proc
          readOnly: true
        - name: etc
          mountPath: /host/etc
          readOnly: true
        - name: tracing
          mountPath: /sys/kernel/tracing
        - name: alertas
          mountPath: /var/log/falco
      volumes:
      - name: proc
        hostPath:
          path: /proc
      - name: etc
        hostPath:
          path: /etc
      - name: tracing
        hostPath:
          path: /sys/kernel/tracing
      - name: alertas
        hostPath:
          path: /var/log/falco
          type: DirectoryOrCreate
      tolerations:
      - operator: Exists
EOF
$K apply -f "$W/falco.yaml" >/dev/null
$K -n la-celaduria run porteria --image="$BUSY" --restart=Never --command -- sleep 86400 >/dev/null
$K -n la-celaduria run verificador --image="$BUSY" --restart=Never --command -- sleep 86400 >/dev/null
$K -n la-celaduria wait --for=condition=Ready pod/porteria pod/verificador --timeout=300s >/dev/null
$K -n la-celaduria rollout status daemonset/falco --timeout=300s

# --------------------------------------- SONDA 2: las camaras de verdad ven el turno
LISTA=no
for i in $(seq 1 24); do
  script -q -c "kubectl --kubeconfig $KC -n la-celaduria exec -it verificador -- sh -c 'echo sonda-de-montaje'" /dev/null >/dev/null 2>&1 || true
  sleep 5
  CID=$($K -n la-celaduria get pod verificador -o jsonpath='{.status.containerStatuses[0].containerID}' | sed 's#containerd://##' | cut -c1-12 || true)
  if "$W/bin/camaras" | grep '^{' | jq -e --arg c "$CID" 'select(.rule=="Terminal shell in container" and .output_fields["container.id"]==$c)' >/dev/null 2>&1; then
    LISTA=si; break
  fi
done
if [ "$LISTA" != "si" ]; then
  echo "ERROR SONDA-CAMARAS-CIEGAS: Falco arranco pero no genero la alerta 'Terminal shell in container'"
  echo "para un shell con terminal dentro de un contenedor de este nodo. En este kernel el motor"
  echo "modern_ebpf no esta viendo las llamadas al sistema, y el Paso 3 seria decoracion."
  echo "El montaje se detiene aqui en vez de entregarle un ejercicio sin piso."
  exit 1
fi
echo "sonda-camaras: Falco con modern_ebpf ve los shells con terminal dentro de los contenedores."

# ------------------------------------------------------------------ Paso 4: el local
cat > "$W/local/caja-registradora.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: el-local
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: caja-registradora
  namespace: el-local
  labels:
    app: caja-registradora
spec:
  replicas: 1
  selector:
    matchLabels:
      app: caja-registradora
  template:
    metadata:
      labels:
        app: caja-registradora
    spec:
      containers:
      - name: caja
        image: $BUSY
        command:
        - sh
        - -c
        - |
          mkdir -p /www /var/log/local
          echo "caja registradora abierta" > /www/index.html
          echo "apertura del turno" >> /var/log/local/ventas.log
          exec httpd -f -p 8080 -h /www
        ports:
        - containerPort: 8080
          name: http
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 3
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: caja-registradora
  namespace: el-local
spec:
  selector:
    app: caja-registradora
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 8080
EOF
$K apply -f "$W/local/caja-registradora.yaml" >/dev/null
$K -n el-local run mandadero --image="$CURL" --restart=Never --command -- sleep 86400 >/dev/null
$K -n el-local rollout status deployment/caja-registradora --timeout=300s
$K -n el-local wait --for=condition=Ready pod/mandadero --timeout=300s >/dev/null

echo ""
echo "kubeconfig privado del laboratorio: $KC"
echo "USE --kubeconfig $KC EN TODOS SUS COMANDOS kubectl."
echo "la minuta (bitacora de auditoria): $W/bin/minuta"
echo "las camaras (alertas de Falco):    $W/bin/camaras"
$K get pods -A -o wide | grep -E 'la-celaduria|el-local|NAME'
echo "montaje listo: el cluster cks-p06 quedo con la minuta abierta, las camaras prendidas y un incidente ya ocurrido."
