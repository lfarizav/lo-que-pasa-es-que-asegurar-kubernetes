#!/usr/bin/env bash
# lab-part-02 - setup
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

KC="$HOME/cks-lab/p02/kubeconfig"
W="$HOME/cks-lab/p02"
NODO="cks-p02-control-plane"
NODO_IMG="kindest/node:v1.34.2@sha256:745f8ed46d8e99517774768227fd1a0af34a6bf395aef9c7ed98fbce0e263918"
BB="busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0"

for tool in kind kubectl docker; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FALTA: $tool - instalelo antes de empezar."; exit 1; }
done

mkdir -p "$W"
cat > "$W/kind.yaml" <<'YAML'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
YAML

kind get clusters 2>/dev/null | grep -qx cks-p02 || \
  kind create cluster --name cks-p02 \
    --kubeconfig "$KC" \
    --image "$NODO_IMG" \
    --config "$W/kind.yaml" \
    --wait 180s

test -f "$KC" || kind export kubeconfig --name cks-p02 --kubeconfig "$KC"
chmod 600 "$KC"
K="kubectl --kubeconfig $KC"
$K wait --for=condition=Ready node --all --timeout=180s

# ---------- prueba de sustrato 1: RBAC autoriza de verdad ----------
RESP=$($K auth can-i delete secrets -n default --as=system:serviceaccount:default:nadie 2>/dev/null || true)
if [ "$RESP" != "no" ]; then
  echo "ERROR SUSTRATO_SIN_RBAC: al preguntar si una ServiceAccount inexistente puede borrar Secrets, este cluster respondio '$RESP' en vez de 'no'. El Paso 1 entero se califica con kubectl auth can-i por los dos lados, y si el modo de autorizacion no niega nada, ese paso no prueba nada. Revise: $K -n kube-system get pod kube-apiserver-$NODO -o yaml | grep authorization-mode"
  exit 1
fi
echo "prueba de sustrato 1 OK: RBAC responde que no a lo que nadie autorizo."

# ---------- la porteria ----------
$K get namespace porteria >/dev/null 2>&1 || $K create namespace porteria >/dev/null

$K apply -f - >/dev/null <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: celador-de-turno
  namespace: porteria
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: celador-sin-llaves
  namespace: porteria
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: llave-maestra-del-celador
  namespace: porteria
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: celador-de-turno
  namespace: porteria
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: turnos-del-mes
  namespace: porteria
data:
  turno-de-la-noche: "celador-de-turno"
  turno-del-dia: "celador-sin-llaves"
---
apiVersion: v1
kind: Secret
metadata:
  name: clave-de-la-reja
  namespace: porteria
type: Opaque
stringData:
  clave: "la-reja-abre-con-4471"
---
apiVersion: v1
kind: Pod
metadata:
  name: garita
  namespace: porteria
spec:
  serviceAccountName: celador-de-turno
  containers:
  - name: garita
    image: $BB
    command: ["sh","-c","sleep 86400"]
    resources:
      requests: {cpu: 50m, memory: 32Mi}
      limits: {cpu: 200m, memory: 128Mi}
YAML

cat > "$W/ronda-nocturna.yaml" <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: ronda-nocturna
  namespace: porteria
spec:
  serviceAccountName: celador-sin-llaves
  containers:
  - name: ronda
    image: $BB
    command: ["sh","-c","while true; do date -u +%Y-%m-%dT%H:%M:%SZ >> /tmp/ronda.log; sleep 3; done"]
    resources:
      requests: {cpu: 50m, memory: 32Mi}
      limits: {cpu: 200m, memory: 128Mi}
YAML
$K apply -f "$W/ronda-nocturna.yaml" >/dev/null

$K -n porteria wait --for=condition=Ready pod/garita --timeout=180s
$K -n porteria wait --for=condition=Ready pod/ronda-nocturna --timeout=180s

# ---------- prueba de sustrato 2: el token se monta solo ----------
HAY=$($K -n porteria exec ronda-nocturna -- sh -c 'ls /var/run/secrets/kubernetes.io/serviceaccount/token >/dev/null 2>&1 && echo HAY || echo NO_HAY' 2>/dev/null | tr -d '\r\n')
if [ "$HAY" != "HAY" ]; then
  echo "ERROR SUSTRATO_SIN_AUTOMOUNT: el Pod ronda-nocturna se creo sin token proyectado en /var/run/secrets/kubernetes.io/serviceaccount, y el Paso 2 consiste justamente en quitar ese montaje. Si ya viene quitado, el paso no cambia nada y la calificacion no significaria nada. Revise: $K -n porteria get pod ronda-nocturna -o yaml | grep -A5 volumes"
  exit 1
fi
echo "prueba de sustrato 2 OK: el token de la ServiceAccount se monta solo cuando nadie lo prohibe."

# ---------- prueba de sustrato 3: NodeRestriction hace cumplir, en los dos sentidos ----------
ETQ="node-restriction.kubernetes.io/sonda-p02=si"
COMO="--as=system:node:$NODO --as-group=system:nodes --as-group=system:authenticated"
SALIDA=$($K label node "$NODO" $ETQ $COMO 2>&1 || true)
if ! echo "$SALIDA" | grep -q "is not allowed to modify labels"; then
  echo "ERROR SUSTRATO_SIN_NODERESTRICTION: con el plugin NodeRestriction activo, el nodo pudo ponerse a si mismo una etiqueta con prefijo node-restriction.kubernetes.io/ y el API server respondio: $SALIDA. El Paso 4 se califica midiendo esa negacion, asi que sin ella el paso seria decoracion. Revise: $K -n kube-system get pod kube-apiserver-$NODO -o jsonpath='{.spec.containers[0].command}'"
  $K label node "$NODO" node-restriction.kubernetes.io/sonda-p02- >/dev/null 2>&1
  exit 1
fi

# falla A del plano de control (carga util opaca y determinista)
echo 'c2VkIC1pICdzLy0tZW5hYmxlLWFkbWlzc2lvbi1wbHVnaW5zPU5vZGVSZXN0cmljdGlvbi8tLWVuYWJsZS1hZG1pc3Npb24tcGx1Z2lucz1MaW1pdFJhbmdlci8nIC9ldGMva3ViZXJuZXRlcy9tYW5pZmVzdHMva3ViZS1hcGlzZXJ2ZXIueWFtbAo=' \
  | base64 -d | docker exec -i "$NODO" sh -s

APAGADO=no
for i in $(seq 1 40); do
  F=$($K -n kube-system get pod kube-apiserver-$NODO -o jsonpath='{.spec.containers[0].command}' 2>/dev/null | tr ',' '\n' | grep -o 'enable-admission-plugins=[^"]*' || true)
  case "$F" in *NodeRestriction*) : ;; ?*) APAGADO=si; break ;; esac
  sleep 5
done
if [ "$APAGADO" != "si" ]; then
  echo "ERROR SUSTRATO_APISERVER_NO_RECARGA: se modifico /etc/kubernetes/manifests/kube-apiserver.yaml dentro del nodo y el kube-apiserver no volvio a arrancar con la bandera nueva en 200 segundos. Sin esa recarga el Paso 4 no se puede ni preparar ni calificar. Revise: docker exec $NODO crictl ps -a | grep apiserver"
  exit 1
fi

SALIDA=$($K label node "$NODO" $ETQ $COMO 2>&1 || true)
if ! echo "$SALIDA" | grep -q "labeled"; then
  echo "ERROR SUSTRATO_NEGACION_AJENA: con NodeRestriction apagado, el nodo SIGUE sin poder ponerse la etiqueta node-restriction.kubernetes.io/, y el API server respondio: $SALIDA. Eso significa que la negacion que el Paso 4 mide no viene del plugin de admision sino de otra cosa, y el paso estaria calificando el control equivocado."
  exit 1
fi
$K label node "$NODO" node-restriction.kubernetes.io/sonda-p02- >/dev/null 2>&1
echo "prueba de sustrato 3 OK: la negacion de la etiqueta restringida viene de NodeRestriction y de nada mas."

# ---------- prueba de sustrato 4: el kubelet autentica, en los dos sentidos ----------
ANTES=$(docker exec "$NODO" sh -c 'curl -sk -o /dev/null -w "%{http_code}" --max-time 10 https://127.0.0.1:10250/pods' 2>/dev/null || true)
if [ "$ANTES" != "401" ] && [ "$ANTES" != "403" ]; then
  echo "ERROR SUSTRATO_KUBELET_ABIERTO_DE_FABRICA: antes de tocar nada, una peticion sin credenciales al puerto 10250 de este nodo devolvio $ANTES en vez de 401 o 403. Este laboratorio parte de un kubelet que autentica, lo rompe a proposito y hace que usted lo arregle; si de fabrica ya viene abierto, el Paso 3 no tendria estado final que medir. Revise: docker exec $NODO cat /var/lib/kubelet/config.yaml"
  exit 1
fi

# falla B del plano de control (carga util opaca y determinista)
echo 'c2VkIC1pICcvXiAgYW5vbnltb3VzOi97bjtzL2VuYWJsZWQ6IGZhbHNlL2VuYWJsZWQ6IHRydWUvfScgL3Zhci9saWIva3ViZWxldC9jb25maWcueWFtbApzZWQgLWkgJ3MvXiAgbW9kZTogV2ViaG9vayQvICBtb2RlOiBBbHdheXNBbGxvdy8nIC92YXIvbGliL2t1YmVsZXQvY29uZmlnLnlhbWwKc3lzdGVtY3RsIHJlc3RhcnQga3ViZWxldAo=' \
  | base64 -d | docker exec -i "$NODO" sh -s

$K wait --for=condition=Ready node/$NODO --timeout=180s >/dev/null
DESPUES=""
for i in $(seq 1 20); do
  DESPUES=$(docker exec "$NODO" sh -c 'curl -sk -o /dev/null -w "%{http_code}" --max-time 10 https://127.0.0.1:10250/pods' 2>/dev/null || true)
  [ "$DESPUES" = "200" ] && break
  sleep 3
done
if [ "$DESPUES" != "200" ]; then
  echo "ERROR SUSTRATO_KUBELET_NO_SE_ABRE: se dejo el kubelet de este nodo con autenticacion anonima y autorizacion AlwaysAllow, se reinicio, y una peticion sin credenciales al puerto 10250 devolvio $DESPUES en vez de 200. El Paso 3 le pide a usted cerrar esa puerta, y si la puerta nunca quedo abierta no hay nada que cerrar. Revise: docker exec $NODO systemctl status kubelet y docker exec $NODO cat /var/lib/kubelet/config.yaml"
  exit 1
fi
echo "prueba de sustrato 4 OK: el puerto 10250 de este nodo quedo respondiendo sin credenciales, que es el estado que a usted le toca revertir."

$K -n porteria wait --for=condition=Ready pod/garita --timeout=180s >/dev/null
$K -n porteria wait --for=condition=Ready pod/ronda-nocturna --timeout=180s >/dev/null

echo "espacio de trabajo listo en $W"
echo "cluster cks-p02 con kubeconfig privado en $KC"
echo "namespace de trabajo: porteria   nodo: $NODO"
$K -n porteria get serviceaccounts,rolebindings,pods
echo "el manifiesto de la ronda nocturna esta en $W/ronda-nocturna.yaml"
echo "el conjunto quedo con dos fallas de endurecimiento puestas a proposito en el plano de control; los Pasos 3 y 4 le dicen que estado final se exige, no donde esta el destornillador."
