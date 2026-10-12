#!/usr/bin/env bash
# lab-part-04 - setup
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

KC="$HOME/cks-lab/p04/kubeconfig"
W="$HOME/cks-lab/p04"
NODO="cks-p04-control-plane"
NODO_IMG="kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5"
BB="busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0"
NGX="nginx:1.29.3-alpine@sha256:b3c656d55d7ad751196f21b7fd2e8d4da9cb430e32f646adcf92441b72f82b14"
CRL="curlimages/curl:8.19.0@sha256:c03110c736db81bbe1be0296f1f1608c81b954b01626bdfb0a8f84e5bd00ff3c"

for tool in kind kubectl docker openssl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FALTA: $tool - instalelo antes de empezar."; exit 1; }
done

mkdir -p "$W/enc" "$W/pki"
chmod 700 "$W/enc"

# ---------- la llave de la caja: nueva en cada instalacion, nunca versionada ----------
if [ ! -f "$W/enc/enc.yaml" ]; then
  LLAVE=$(head -c 32 /dev/urandom | base64)
  cat > "$W/enc/enc.yaml" <<YAML
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: llave-de-la-caja
              secret: $LLAVE
      - identity: {}
YAML
  chmod 600 "$W/enc/enc.yaml"
fi

cat > "$W/kind.yaml" <<YAML
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
  - hostPath: $W/enc
    containerPath: /etc/kubernetes/enc
    readOnly: true
kubeadmConfigPatches:
- |
  kind: ClusterConfiguration
  apiServer:
    extraArgs:
    - name: encryption-provider-config
      value: /etc/kubernetes/enc/enc.yaml
    extraVolumes:
    - name: enc
      hostPath: /etc/kubernetes/enc
      mountPath: /etc/kubernetes/enc
      readOnly: true
      pathType: DirectoryOrCreate
YAML

kind get clusters 2>/dev/null | grep -qx cks-p04 || \
  kind create cluster --name cks-p04 \
    --kubeconfig "$KC" \
    --image "$NODO_IMG" \
    --config "$W/kind.yaml" \
    --wait 180s

test -f "$KC" || kind export kubeconfig --name cks-p04 --kubeconfig "$KC"
chmod 600 "$KC"
kubectl --kubeconfig "$KC" wait --for=condition=Ready node --all --timeout=180s

kubectl --kubeconfig "$KC" get namespace sonda-p04 >/dev/null 2>&1 || \
  kubectl --kubeconfig "$KC" create namespace sonda-p04 >/dev/null

# ---------- prueba de sustrato 1: Pod Security Admission se hace cumplir ----------
# linea base: sin etiquetas, un Pod que corre como root y sin seccomp entra sin problema.
if ! kubectl --kubeconfig "$KC" -n sonda-p04 run sonda-linea-base \
  --image="$BB" --restart=Never --command -- sleep 120 >/dev/null 2>&1; then
  echo "ERROR SUSTRATO_LINEA_BASE_PSA: un namespace sin ninguna etiqueta de Pod Security Admission rechazo un Pod corriente. Algo mas en este cluster esta admitiendo (un webhook, una politica externa) y la medicion de PSA de este laboratorio no significaria nada."
  exit 1
fi
kubectl --kubeconfig "$KC" -n sonda-p04 delete pod sonda-linea-base --wait=false >/dev/null 2>&1

# control: se sube el reglamento a restricted.
kubectl --kubeconfig "$KC" label namespace sonda-p04 \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest --overwrite >/dev/null

# re-prueba: el mismo Pod corriente ahora tiene que ser rechazado.
SALIDA=$(kubectl --kubeconfig "$KC" -n sonda-p04 run sonda-restricted \
  --image="$BB" --restart=Never --command -- sleep 120 2>&1 || true)
if ! echo "$SALIDA" | grep -q "violates PodSecurity"; then
  echo "ERROR SUSTRATO_SIN_PSA: con el namespace etiquetado enforce=restricted, este cluster acepto un Pod que corre como root, sin seccompProfile y sin soltar capabilities. Pod Security Admission no esta rechazando nada, y los Pasos 1 y 3 completos serian decoracion. Lo que devolvio el API server fue: $SALIDA. Revise que el plugin de admision PodSecurity este activo: kubectl --kubeconfig $KC -n kube-system get pod -l component=kube-apiserver -o yaml | grep -i admission"
  kubectl --kubeconfig "$KC" delete namespace sonda-p04 --wait=false >/dev/null 2>&1
  exit 1
fi
echo "prueba de sustrato 1 OK: baseline dejaba pasar ese Pod y restricted lo rechaza. La portería mide, no adivina."

# ---------- prueba de sustrato 2: los Secrets quedan cifrados en etcd ----------
if ! docker exec "$NODO" grep -q -- "--encryption-provider-config=/etc/kubernetes/enc/enc.yaml" /etc/kubernetes/manifests/kube-apiserver.yaml; then
  echo "ERROR SUSTRATO_SIN_ENCRYPTION_CONFIG: el manifiesto del kube-apiserver en este nodo no trae --encryption-provider-config. El parche de kubeadm no se aplico y el Paso 2 no tendria nada que medir. Revise: docker exec $NODO grep -n encryption /etc/kubernetes/manifests/kube-apiserver.yaml"
  exit 1
fi

ETCD_IMG=$(docker exec "$NODO" grep -m1 'image:' /etc/kubernetes/manifests/etcd.yaml | awk '{print $2}' || true)
docker exec "$NODO" sh -c "test -x /usr/local/bin/etcdctl || (mkdir -p /mnt/imagen-de-etcd && ctr -n k8s.io images mount $ETCD_IMG /mnt/imagen-de-etcd >/dev/null && cp /mnt/imagen-de-etcd/usr/local/bin/etcdctl /usr/local/bin/etcdctl && chmod +x /usr/local/bin/etcdctl && ctr -n k8s.io images unmount /mnt/imagen-de-etcd >/dev/null)"
docker exec "$NODO" test -x /usr/local/bin/etcdctl || {
  echo "ERROR SUSTRATO_SIN_ETCDCTL: no se pudo sacar el binario etcdctl de la imagen $ETCD_IMG que ya vive en el nodo. Sin etcdctl no hay forma de leer etcd por debajo del API server y el Paso 2 no se puede calificar. Revise: docker exec $NODO ctr -n k8s.io images ls -q | grep etcd"
  exit 1
}

ETCDF="--endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"
kubectl --kubeconfig "$KC" -n sonda-p04 create secret generic sonda-de-cifrado \
  --from-literal=clave='SONDA-DE-SUSTRATO-EN-CLARO' >/dev/null
CRUDO=$(docker exec "$NODO" sh -c "etcdctl $ETCDF get /registry/secrets/sonda-p04/sonda-de-cifrado" 2>/dev/null | tr -d '\0' || true)
if ! echo "$CRUDO" | grep -qa 'k8s:enc:'; then
  echo "ERROR SUSTRATO_SIN_CIFRADO_EN_REPOSO: el Secret recien creado NO lleva el prefijo k8s:enc: en etcd. El flag existe pero el cifrado no se esta aplicando, y el Paso 2 entero es una afirmacion sin medida. Revise el archivo montado: docker exec $NODO cat /etc/kubernetes/enc/enc.yaml"
  kubectl --kubeconfig "$KC" delete namespace sonda-p04 --wait=false >/dev/null 2>&1
  exit 1
fi
if echo "$CRUDO" | grep -qa 'SONDA-DE-SUSTRATO-EN-CLARO'; then
  echo "ERROR SUSTRATO_TEXTO_PLANO_EN_ETCD: el valor del Secret aparece en claro dentro de etcd pese al prefijo. El proveedor identity esta ganando o la lista de recursos no incluye secrets. Revise: docker exec $NODO cat /etc/kubernetes/enc/enc.yaml"
  kubectl --kubeconfig "$KC" delete namespace sonda-p04 --wait=false >/dev/null 2>&1
  exit 1
fi
echo "prueba de sustrato 2 OK: un Secret nuevo queda cifrado en etcd y su texto no aparece en claro."

# ---------- prueba de sustrato 3: readOnlyRootFilesystem y drop ALL se hacen cumplir ----------
kubectl --kubeconfig "$KC" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: sonda-de-uniforme
  namespace: sonda-p04
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: c
    image: $BB
    command: ["sh","-c","while true; do date > /tmp/sonda.txt; sleep 2; done"]
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
kubectl --kubeconfig "$KC" -n sonda-p04 wait --for=condition=Ready pod/sonda-de-uniforme --timeout=180s >/dev/null 2>&1
if kubectl --kubeconfig "$KC" -n sonda-p04 exec sonda-de-uniforme -- sh -c 'touch /sonda-en-la-raiz' >/dev/null 2>&1; then
  echo "ERROR SUSTRATO_SIN_ROOTFS_SOLO_LECTURA: con readOnlyRootFilesystem en true, el contenedor pudo escribir en la raiz. El kubelet no esta montando la raiz en solo lectura y el Paso 3 no significaria nada. Revise: kubectl --kubeconfig $KC -n sonda-p04 exec sonda-de-uniforme -- grep ' / ' /proc/mounts"
  kubectl --kubeconfig "$KC" delete namespace sonda-p04 --wait=false >/dev/null 2>&1
  exit 1
fi
CAPS=$(kubectl --kubeconfig "$KC" -n sonda-p04 exec sonda-de-uniforme -- sh -c 'grep ^CapEff /proc/1/status' 2>/dev/null | awk '{print $2}' || true)
if [ "$CAPS" != "0000000000000000" ]; then
  echo "ERROR SUSTRATO_SIN_DROP_DE_CAPABILITIES: con capabilities.drop ALL, el proceso 1 del contenedor conserva CapEff=$CAPS en vez de 0000000000000000. El runtime no esta soltando las capabilities y el Paso 3 no se puede calificar desde adentro. Revise: kubectl --kubeconfig $KC -n sonda-p04 exec sonda-de-uniforme -- cat /proc/1/status"
  kubectl --kubeconfig "$KC" delete namespace sonda-p04 --wait=false >/dev/null 2>&1
  exit 1
fi
echo "prueba de sustrato 3 OK: la raiz queda en solo lectura y el proceso se queda sin una sola capability."
kubectl --kubeconfig "$KC" delete namespace sonda-p04 --wait=false >/dev/null 2>&1

# ---------- la torre A: el reglamento flojo y el inquilino que no cabe ----------
kubectl --kubeconfig "$KC" get namespace torre-a >/dev/null 2>&1 || \
  kubectl --kubeconfig "$KC" create namespace torre-a >/dev/null
kubectl --kubeconfig "$KC" label namespace torre-a \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/enforce-version=latest --overwrite >/dev/null

test -f "$W/inquilino.yaml" || cat > "$W/inquilino.yaml" <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: inquilino
  namespace: torre-a
spec:
  containers:
  - name: inquilino
    image: $BB
    command: ["sh","-c","sleep 86400"]
    securityContext:
      privileged: true
YAML

# ---------- la tienda: vacia, la caja fuerte la abre usted ----------
kubectl --kubeconfig "$KC" get namespace tienda >/dev/null 2>&1 || \
  kubectl --kubeconfig "$KC" create namespace tienda >/dev/null

# ---------- el apartamento 303: vacio, el uniforme lo cose usted ----------
kubectl --kubeconfig "$KC" get namespace apartamento-303 >/dev/null 2>&1 || \
  kubectl --kubeconfig "$KC" create namespace apartamento-303 >/dev/null

# ---------- el citofono: PKI del conjunto, y una CA de la calle que no es del conjunto ----------
if [ ! -f "$W/pki/vecino.crt" ]; then
  printf 'subjectAltName=DNS:citofono,DNS:citofono.citofono.svc,DNS:citofono.citofono.svc.cluster.local\nextendedKeyUsage=serverAuth\n' > "$W/pki/servidor.ext"
  printf 'extendedKeyUsage=clientAuth\n' > "$W/pki/cliente.ext"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$W/pki/ca.key" -out "$W/pki/ca.crt" \
    -days 365 -subj "/CN=ca-del-conjunto" >/dev/null 2>&1
  openssl req -newkey rsa:2048 -nodes -keyout "$W/pki/servidor.key" -out "$W/pki/servidor.csr" \
    -subj "/CN=citofono" >/dev/null 2>&1
  openssl x509 -req -in "$W/pki/servidor.csr" -CA "$W/pki/ca.crt" -CAkey "$W/pki/ca.key" \
    -CAcreateserial -out "$W/pki/servidor.crt" -days 365 -extfile "$W/pki/servidor.ext" >/dev/null 2>&1
  openssl req -newkey rsa:2048 -nodes -keyout "$W/pki/vecino.key" -out "$W/pki/vecino.csr" \
    -subj "/CN=apartamento-303" >/dev/null 2>&1
  openssl x509 -req -in "$W/pki/vecino.csr" -CA "$W/pki/ca.crt" -CAkey "$W/pki/ca.key" \
    -CAcreateserial -out "$W/pki/vecino.crt" -days 365 -extfile "$W/pki/cliente.ext" >/dev/null 2>&1
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$W/pki/impostor-ca.key" -out "$W/pki/impostor-ca.crt" \
    -days 365 -subj "/CN=ca-de-la-calle" >/dev/null 2>&1
  openssl req -newkey rsa:2048 -nodes -keyout "$W/pki/impostor.key" -out "$W/pki/impostor.csr" \
    -subj "/CN=apartamento-303" >/dev/null 2>&1
  openssl x509 -req -in "$W/pki/impostor.csr" -CA "$W/pki/impostor-ca.crt" -CAkey "$W/pki/impostor-ca.key" \
    -CAcreateserial -out "$W/pki/impostor.crt" -days 365 -extfile "$W/pki/cliente.ext" >/dev/null 2>&1
  chmod 600 "$W/pki"/*.key
fi

kubectl --kubeconfig "$KC" get namespace citofono >/dev/null 2>&1 || \
  kubectl --kubeconfig "$KC" create namespace citofono >/dev/null
kubectl --kubeconfig "$KC" -n citofono get secret citofono-tls >/dev/null 2>&1 || \
  kubectl --kubeconfig "$KC" -n citofono create secret tls citofono-tls \
    --cert="$W/pki/servidor.crt" --key="$W/pki/servidor.key" >/dev/null
kubectl --kubeconfig "$KC" -n citofono get secret ca-del-conjunto >/dev/null 2>&1 || \
  kubectl --kubeconfig "$KC" -n citofono create secret generic ca-del-conjunto \
    --from-file=ca.crt="$W/pki/ca.crt" >/dev/null
kubectl --kubeconfig "$KC" -n citofono get secret carnet-del-vecino >/dev/null 2>&1 || \
  kubectl --kubeconfig "$KC" -n citofono create secret generic carnet-del-vecino \
    --from-file=vecino.crt="$W/pki/vecino.crt" \
    --from-file=vecino.key="$W/pki/vecino.key" \
    --from-file=ca.crt="$W/pki/ca.crt" >/dev/null
kubectl --kubeconfig "$KC" -n citofono get secret carnet-de-la-calle >/dev/null 2>&1 || \
  kubectl --kubeconfig "$KC" -n citofono create secret generic carnet-de-la-calle \
    --from-file=impostor.crt="$W/pki/impostor.crt" \
    --from-file=impostor.key="$W/pki/impostor.key" >/dev/null

cat > "$W/citofono.conf" <<'CONF'
server {
    listen 8443 ssl;
    server_name citofono;

    ssl_certificate        /etc/nginx/tls/tls.crt;
    ssl_certificate_key    /etc/nginx/tls/tls.key;
    ssl_client_certificate /etc/nginx/ca/ca.crt;
    ssl_verify_client      off;

    location / {
        default_type text/plain;
        return 200 "citofono del 303: adelante\n";
    }
}
CONF
kubectl --kubeconfig "$KC" -n citofono get configmap citofono-conf >/dev/null 2>&1 || \
  kubectl --kubeconfig "$KC" -n citofono create configmap citofono-conf \
    --from-file=citofono.conf="$W/citofono.conf" >/dev/null

cat > "$W/citofono-pod.yaml" <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: citofono
  namespace: citofono
  labels:
    app: citofono
spec:
  containers:
  - name: nginx
    image: $NGX
    ports:
    - containerPort: 8443
    volumeMounts:
    - name: conf
      mountPath: /etc/nginx/conf.d/citofono.conf
      subPath: citofono.conf
    - name: tls
      mountPath: /etc/nginx/tls
      readOnly: true
    - name: ca
      mountPath: /etc/nginx/ca
      readOnly: true
  volumes:
  - name: conf
    configMap:
      name: citofono-conf
  - name: tls
    secret:
      secretName: citofono-tls
  - name: ca
    secret:
      secretName: ca-del-conjunto
YAML
kubectl --kubeconfig "$KC" apply -f "$W/citofono-pod.yaml" >/dev/null

kubectl --kubeconfig "$KC" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Service
metadata:
  name: citofono
  namespace: citofono
spec:
  selector:
    app: citofono
  ports:
  - port: 8443
    targetPort: 8443
---
apiVersion: v1
kind: Pod
metadata:
  name: vecino
  namespace: citofono
spec:
  containers:
  - name: curl
    image: $CRL
    command: ["sleep","86400"]
    volumeMounts:
    - name: carnet
      mountPath: /carnet
      readOnly: true
    - name: calle
      mountPath: /calle
      readOnly: true
  volumes:
  - name: carnet
    secret:
      secretName: carnet-del-vecino
  - name: calle
    secret:
      secretName: carnet-de-la-calle
YAML
kubectl --kubeconfig "$KC" -n citofono wait --for=condition=Ready pod/citofono pod/vecino --timeout=180s

# ---------- prueba de sustrato 4: el citofono responde por TLS y hoy le abre a cualquiera ----------
CODIGO=""
for i in $(seq 1 20); do
  CODIGO=$(kubectl --kubeconfig "$KC" -n citofono exec vecino -- \
    curl -s -o /dev/null -w '%{http_code}' --cacert /carnet/ca.crt https://citofono:8443/ 2>/dev/null || true)
  [ "$CODIGO" = "200" ] && break
  sleep 3
done
if [ "$CODIGO" != "200" ]; then
  echo "ERROR SUSTRATO_SIN_CITOFONO: una peticion TLS del Pod vecino al Service citofono devolvio '$CODIGO' en vez de 200 antes de que usted exija ningun carne. Si la linea base no funciona, medir el efecto de exigir carne en el Paso 4 no probaria nada. Revise: kubectl --kubeconfig $KC -n citofono logs citofono y kubectl --kubeconfig $KC -n citofono get endpointslices"
  exit 1
fi
echo "prueba de sustrato 4 OK: el citofono contesta por TLS y hoy le abre a cualquiera que toque (codigo $CODIGO)."

echo "espacio de trabajo listo en $W"
echo "cluster cks-p04 con kubeconfig privado en $KC"
echo "namespaces de trabajo: torre-a, tienda, apartamento-303, citofono"
kubectl --kubeconfig "$KC" get namespace torre-a -o jsonpath='reglamento_de_la_torre_a={.metadata.labels.pod-security\.kubernetes\.io/enforce}{"\n"}'
echo "el manifiesto del inquilino que no cabe esta en $W/inquilino.yaml"
echo "la configuracion del citofono esta en el ConfigMap citofono-conf del namespace citofono"
