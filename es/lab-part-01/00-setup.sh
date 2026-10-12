#!/usr/bin/env bash
# lab-part-01 - setup
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

mkdir -p ~/cks-lab/p01
cd ~/cks-lab/p01

for tool in kind kubectl docker curl openssl base64 sha256sum dd; do
  command -v "$tool" >/dev/null 2>&1 || echo "FALTA: $tool - instalelo antes de continuar."
done

for p in 8091 8449; do
  ss -ltn "sport = :$p" 2>/dev/null | grep -q LISTEN && echo "OCUPADO: el puerto $p del host esta en uso; cambielo en kind-p01.yaml."
done

cat > kind-p01.yaml <<'YAML'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  podSubnet: "10.244.0.0/16"
nodes:
- role: control-plane
  image: kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5
  extraPortMappings:
  - containerPort: 80
    hostPort: 8091
    protocol: TCP
  - containerPort: 443
    hostPort: 8449
    protocol: TCP
YAML

kind create cluster --name cks-p01 \
  --kubeconfig ~/cks-lab/p01/kubeconfig \
  --config kind-p01.yaml

K="kubectl --kubeconfig $HOME/cks-lab/p01/kubeconfig"

echo "instalando Calico v3.32.1 (sin el, el Paso 1 no probaria nada)"

# Los CRD van primero y explicitos. El operador tambien los instala solo al
# arrancar, pero unos segundos DESPUES de que su Deployment queda rolled out,
# asi que aplicar el recurso Installation enseguida falla con
# "no matches for kind Installation" y el resto se cae en cascada.
$K apply --server-side \
  -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/operator-crds.yaml
$K wait --for=condition=established --timeout=300s crd/installations.operator.tigera.io

$K apply --server-side \
  -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/tigera-operator.yaml
$K -n tigera-operator rollout status deploy/tigera-operator --timeout=300s

cat > calico-installation.yaml <<'YAML'
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - name: default-ipv4-ippool
      blockSize: 26
      cidr: 10.244.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
YAML
$K apply -f calico-installation.yaml

echo "esperando a que Calico quede disponible..."
LISTO=""
for _ in $(seq 1 45); do
  LISTO=$($K get tigerastatus calico -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)
  [ "$LISTO" = "True" ] && break
  sleep 10
done
if [ "$LISTO" != "True" ]; then
  echo "ERROR SUSTRATO-SIN-CNI: Calico nunca quedo disponible en este cluster."
  echo "Sin un CNI instalado los Pods no consiguen direccion IP y NADA de este"
  echo "laboratorio funciona. Revise: \$K get tigerastatus; \$K -n calico-system get pods"
  exit 1
fi
$K wait --for=condition=Ready nodes --all --timeout=300s

# -------------------------------------------------------------------------
# PRUEBA DEL SUSTRATO: no asumimos que el CNI aplica NetworkPolicy, lo MEDIMOS.
# Linea base abierta -> negacion total -> la sonda bloqueada TIENE que fallar.
# -------------------------------------------------------------------------
echo "midiendo si este cluster de verdad APLICA NetworkPolicy..."
BB=busybox:1.37@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0
NG=nginx:1.29-alpine@sha256:5616878291a2eed594aee8db4dade5878cf7edcb475e59193904b198d9b830de
$K create namespace prueba-del-celador
$K -n prueba-del-celador run servidor --image=$NG --labels=rol=servidor --port=80
$K -n prueba-del-celador run cliente  --image=$BB --command -- sleep 600
$K -n prueba-del-celador wait --for=condition=Ready pod --all --timeout=300s
IP_PRUEBA=$($K -n prueba-del-celador get pod servidor -o jsonpath='{.status.podIP}' || true)

if ! $K -n prueba-del-celador exec cliente -- wget -q -T 5 -O- "http://$IP_PRUEBA" >/dev/null 2>&1; then
  echo "ERROR SUSTRATO-SIN-TRAFICO: la linea base fallo, un Pod no le habla a otro"
  echo "ni siquiera SIN politicas. El modelo de red de Kubernetes dice que deberia."
  echo "Revise el CNI antes de continuar: \$K -n calico-system get pods"
  $K delete namespace prueba-del-celador --wait=false
  exit 1
fi

cat > prueba-negar-todo.yaml <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prueba-negar-todo
  namespace: prueba-del-celador
spec:
  podSelector: {}
  policyTypes:
  - Ingress
YAML
$K apply -f prueba-negar-todo.yaml
sleep 10

if $K -n prueba-del-celador exec cliente -- wget -q -T 5 -O- "http://$IP_PRUEBA" >/dev/null 2>&1; then
  echo "ERROR SUSTRATO-SIN-NETWORKPOLICY: se aplico una politica de negacion total"
  echo "y el trafico SIGUIO pasando. Este cluster guarda los NetworkPolicy en la API"
  echo "pero no los aplica: es el celador de mentiras del Capitulo 1."
  echo "El Paso 1 de este laboratorio no probaria absolutamente nada asi."
  echo "Revise que el cluster se haya creado con disableDefaultCNI: true y que"
  echo "Calico este vivo: \$K get tigerastatus; \$K -n calico-system get pods"
  $K delete namespace prueba-del-celador --wait=false
  exit 1
fi
echo "OK: el sustrato APLICA NetworkPolicy (linea base paso, con negacion total fallo)."
$K delete namespace prueba-del-celador --wait=false

echo "instalando ingress-nginx controller-v1.15.1 (ultima version del proyecto, ya retirado)"
$K apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/kind/deploy.yaml
# rollout status espera al Deployment, que existe desde el apply; un wait sobre los
# Pods falla con "no matching resources" si todavia no se crearon.
$K -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s

for ns in la-torre-tres la-porteria; do
  $K create namespace "$ns"
done

# --- Paso 1: los tres vecinos ya viven en la torre. Usted solo escribe el reglamento.
$K -n la-torre-tres run el-apartamento-301 --image=$NG --labels=rol=apartamento --port=80
$K -n la-torre-tres expose pod el-apartamento-301 --name=citofono-301 --port=80 --target-port=80
$K -n la-torre-tres run el-vecino-autorizado      --image=$BB --labels=visita=autorizada --command -- sleep 36000
$K -n la-torre-tres run el-desconocido-del-portal --image=$BB --labels=visita=negada     --command -- sleep 36000
$K -n la-torre-tres wait --for=condition=Ready pod --all --timeout=300s

# --- Paso 3: el citofono ya esta instalado y contesta por HTTP simple.
#     Lo que falta es la cedula de la porteria, y esa la trae usted.
cat > citofono.yaml <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: contenido-porteria
  namespace: la-porteria
data:
  index.html: |
    LA PORTERIA CON CEDULA VERIFICADA
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: citofono
  namespace: la-porteria
spec:
  replicas: 1
  selector:
    matchLabels:
      app: citofono
  template:
    metadata:
      labels:
        app: citofono
    spec:
      containers:
      - name: web
        image: $NG
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        configMap:
          name: contenido-porteria
---
apiVersion: v1
kind: Service
metadata:
  name: citofono
  namespace: la-porteria
spec:
  selector:
    app: citofono
  ports:
  - name: http
    port: 80
    targetPort: 80
YAML
$K apply -f citofono.yaml
$K -n la-porteria rollout status deploy/citofono --timeout=300s

# --- Paso 2: el manifiesto de kube-bench queda escrito, fijado por digest.
#     Se deja en el espacio de trabajo para que usted lo corra cuando quiera.
cat > kube-bench-job.yaml <<'YAML'
apiVersion: batch/v1
kind: Job
metadata:
  name: kube-bench
  namespace: default
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app: kube-bench
    spec:
      hostPID: true
      nodeSelector:
        node-role.kubernetes.io/control-plane: ""
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      restartPolicy: Never
      containers:
      - name: kube-bench
        image: docker.io/aquasec/kube-bench:v0.16.0@sha256:75506f222d1eb6ce2a751a5533bdc0a3b54c898e2e49e7751d0ee22cfb862679
        command: ["kube-bench","run","--targets=master,controlplane,etcd,policies"]
        volumeMounts:
        - {name: var-lib-etcd, mountPath: /var/lib/etcd, readOnly: true}
        - {name: var-lib-kubelet, mountPath: /var/lib/kubelet, readOnly: true}
        - {name: var-lib-kube-scheduler, mountPath: /var/lib/kube-scheduler, readOnly: true}
        - {name: var-lib-kube-controller-manager, mountPath: /var/lib/kube-controller-manager, readOnly: true}
        - {name: etc-systemd, mountPath: /etc/systemd, readOnly: true}
        - {name: lib-systemd, mountPath: /lib/systemd/, readOnly: true}
        - {name: srv-kubernetes, mountPath: /srv/kubernetes/, readOnly: true}
        - {name: etc-kubernetes, mountPath: /etc/kubernetes, readOnly: true}
        - {name: usr-bin, mountPath: /usr/local/mount-from-host/bin, readOnly: true}
        - {name: etc-cni-netd, mountPath: /etc/cni/net.d/, readOnly: true}
        - {name: opt-cni-bin, mountPath: /opt/cni/bin/, readOnly: true}
      volumes:
      - {name: var-lib-etcd, hostPath: {path: /var/lib/etcd}}
      - {name: var-lib-kubelet, hostPath: {path: /var/lib/kubelet}}
      - {name: var-lib-kube-scheduler, hostPath: {path: /var/lib/kube-scheduler}}
      - {name: var-lib-kube-controller-manager, hostPath: {path: /var/lib/kube-controller-manager}}
      - {name: etc-systemd, hostPath: {path: /etc/systemd}}
      - {name: lib-systemd, hostPath: {path: /lib/systemd}}
      - {name: srv-kubernetes, hostPath: {path: /srv/kubernetes}}
      - {name: etc-kubernetes, hostPath: {path: /etc/kubernetes}}
      - {name: usr-bin, hostPath: {path: /usr/bin}}
      - {name: etc-cni-netd, hostPath: {path: /etc/cni/net.d/}}
      - {name: opt-cni-bin, hostPath: {path: /opt/cni/bin/}}
YAML

mkdir -p ~/cks-lab/p01/binario

echo "espacio de trabajo listo en ~/cks-lab/p01"
echo "kubeconfig privado: ~/cks-lab/p01/kubeconfig (su ~/.kube/config no fue tocado)"
