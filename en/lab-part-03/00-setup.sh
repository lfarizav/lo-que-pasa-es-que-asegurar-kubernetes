#!/usr/bin/env bash
# lab-part-03 - setup
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

KC="$HOME/cks-lab/p03/kubeconfig"
W="$HOME/cks-lab/p03"
NODO="cks-p03-control-plane"
NODO_IMG="kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5"
BB="busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0"

for tool in kind kubectl docker; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FALTA: $tool - instalelo antes de empezar."; exit 1; }
done

HAB=$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)
if [ "$HAB" != "Y" ]; then
  echo "ERROR SUSTRATO_SIN_APPARMOR_EN_EL_HOST: /sys/module/apparmor/parameters/enabled devolvio '$HAB' en vez de 'Y'. Un nodo de kind comparte el kernel de esta maquina, asi que sin AppArmor en el kernel del host no hay AppArmor adentro del nodo y el Paso 3 estaria calificando un control que nadie aplica. Revise que su distribucion traiga AppArmor (Ubuntu y Debian si, muchas otras no) y que este en la lista de LSM activos: cat /sys/kernel/security/lsm. Los Pasos 1, 2 y 4 funcionarian en esta maquina, pero este laboratorio no arranca a medias."
  exit 1
fi

mkdir -p "$W"
cat > "$W/kind.yaml" <<'YAML'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
YAML

kind get clusters 2>/dev/null | grep -qx cks-p03 || \
  kind create cluster --name cks-p03 \
    --kubeconfig "$KC" \
    --image "$NODO_IMG" \
    --config "$W/kind.yaml" \
    --wait 180s

test -f "$KC" || kind export kubeconfig --name cks-p03 --kubeconfig "$KC"
chmod 600 "$KC"
kubectl --kubeconfig "$KC" wait --for=condition=Ready node --all --timeout=180s

# ---------- habilitar AppArmor dentro del nodo ----------
docker exec "$NODO" sh -c 'mountpoint -q /sys/kernel/security || mount -t securityfs securityfs /sys/kernel/security' || {
  echo "ERROR SUSTRATO_SIN_SECURITYFS: no se pudo montar securityfs en /sys/kernel/security dentro del nodo $NODO. Sin securityfs el kubelet reporta 'AppArmor is not enabled on the host' y ningun Pod con appArmorProfile arranca. Revise que el contenedor del nodo sea privilegiado: docker inspect $NODO --format '{{.HostConfig.Privileged}}'"
  exit 1
}

docker exec "$NODO" sh -c 'command -v apparmor_parser >/dev/null 2>&1 || { apt-get update -qq >/dev/null 2>&1 && cd /tmp && apt-get download -qq apparmor >/dev/null 2>&1 && dpkg-deb -x apparmor_*.deb / ; }' >/dev/null 2>&1
docker exec "$NODO" sh -c 'command -v apparmor_parser >/dev/null 2>&1' || {
  echo "ERROR SUSTRATO_SIN_PARSER: apparmor_parser no quedo instalado dentro del nodo $NODO. Se extrae del paquete Debian con dpkg-deb -x, a proposito, para no ejecutar el postinst del paquete, que recargaria todos los perfiles de /etc/apparmor.d del nodo en el kernel de SU maquina. Sin el parser, containerd responde 'apparmor is not supported' y el Paso 3 no puede correr. Compruebe que el nodo tenga salida a internet: docker exec $NODO apt-get update"
  exit 1
}

docker exec "$NODO" systemctl restart containerd
docker exec "$NODO" systemctl restart kubelet
for i in $(seq 1 60); do
  kubectl --kubeconfig "$KC" get --raw=/healthz >/dev/null 2>&1 && break
  sleep 3
done
kubectl --kubeconfig "$KC" wait --for=condition=Ready node --all --timeout=180s

kubectl --kubeconfig "$KC" get namespace sonda-p03 >/dev/null 2>&1 || \
  kubectl --kubeconfig "$KC" create namespace sonda-p03 >/dev/null

# ---------- prueba de sustrato 1: seccomp RuntimeDefault bloquea de verdad ----------
kubectl --kubeconfig "$KC" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: sonda-sin-uniforme
  namespace: sonda-p03
spec:
  securityContext:
    seccompProfile:
      type: Unconfined
  containers:
  - name: c
    image: $BB
    command: ["sh","-c","sleep 900"]
---
apiVersion: v1
kind: Pod
metadata:
  name: sonda-con-uniforme
  namespace: sonda-p03
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: c
    image: $BB
    command: ["sh","-c","sleep 900"]
YAML
kubectl --kubeconfig "$KC" -n sonda-p03 wait --for=condition=Ready pod/sonda-sin-uniforme pod/sonda-con-uniforme --timeout=180s >/dev/null

if ! kubectl --kubeconfig "$KC" -n sonda-p03 exec sonda-sin-uniforme -- unshare -U true >/dev/null 2>&1; then
  echo "ERROR SUSTRATO_SIN_LINEA_BASE: un contenedor con seccompProfile Unconfined no logro crear un user namespace con unshare -U. Ese es el caso de referencia del Paso 1: si la llamada ya falla sin seccomp, comparar contra RuntimeDefault no prueba nada, porque el bloqueo vendria de otra parte. Revise si su kernel restringe los user namespaces sin privilegios: sysctl kernel.unprivileged_userns_clone y sysctl kernel.apparmor_restrict_unprivileged_userns"
  exit 1
fi
if kubectl --kubeconfig "$KC" -n sonda-p03 exec sonda-con-uniforme -- unshare -U true >/dev/null 2>&1; then
  echo "ERROR SUSTRATO_SIN_SECCOMP: un contenedor con seccompProfile RuntimeDefault logro hacer unshare -U, que el perfil por defecto de containerd no permite. Eso significa que el runtime no esta aplicando su perfil por defecto y el Paso 1 entero seria decoracion. Revise el modo seccomp real del proceso: kubectl --kubeconfig $KC -n sonda-p03 exec sonda-con-uniforme -- grep Seccomp /proc/1/status"
  exit 1
fi
MODO=$(kubectl --kubeconfig "$KC" -n sonda-p03 exec sonda-con-uniforme -- sh -c 'grep ^Seccomp: /proc/1/status' 2>/dev/null | awk '{print $2}' || true)
if [ "$MODO" != "2" ]; then
  echo "ERROR SUSTRATO_SIN_FILTRO: /proc/1/status dentro del contenedor con RuntimeDefault reporta Seccomp '$MODO' en vez de 2 (SECCOMP_MODE_FILTER). Sin filtro cargado no hay nada que calificar en el Paso 1."
  exit 1
fi
echo "prueba de sustrato 1 OK: RuntimeDefault bloquea unshare -U y el proceso queda en Seccomp modo 2."

# ---------- prueba de sustrato 2: un perfil Localhost llega al contenedor ----------
docker exec "$NODO" sh -c 'mkdir -p /var/lib/kubelet/seccomp/profiles && cat > /var/lib/kubelet/seccomp/profiles/sonda.json <<JSON
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "architectures": ["SCMP_ARCH_X86_64","SCMP_ARCH_X86","SCMP_ARCH_X32"],
  "syscalls": [
    {"names": ["chmod","fchmod","fchmodat","fchmodat2"], "action": "SCMP_ACT_ERRNO", "errnoRet": 1}
  ]
}
JSON'
kubectl --kubeconfig "$KC" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: sonda-local
  namespace: sonda-p03
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/sonda.json
  containers:
  - name: c
    image: $BB
    command: ["sh","-c","sleep 900"]
YAML
if ! kubectl --kubeconfig "$KC" -n sonda-p03 wait --for=condition=Ready pod/sonda-local --timeout=120s >/dev/null 2>&1; then
  RAZON=$(kubectl --kubeconfig "$KC" -n sonda-p03 get pod sonda-local -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}: {.status.containerStatuses[0].state.waiting.message}' 2>/dev/null || true)
  echo "ERROR SUSTRATO_SIN_PERFIL_LOCALHOST: el Pod de sonda con seccompProfile Localhost no llego a Ready. El kubelet dijo: $RAZON. La raiz de perfiles por defecto es /var/lib/kubelet/seccomp y localhostProfile es una ruta relativa a esa raiz; si el archivo no esta, el contenedor falla con CreateContainerError. El Paso 2 completo depende de esto."
  exit 1
fi
kubectl --kubeconfig "$KC" -n sonda-p03 exec sonda-local -- touch /tmp/sonda >/dev/null 2>&1 || {
  echo "ERROR SUSTRATO_PERFIL_DEMASIADO_ESTRECHO: dentro del Pod con el perfil Localhost de sonda ni siquiera se pudo crear un archivo con touch. El perfil de prueba tiene defaultAction SCMP_ACT_ALLOW, asi que esto no deberia pasar y apunta a un problema del runtime, no del perfil."
  exit 1
}
if kubectl --kubeconfig "$KC" -n sonda-p03 exec sonda-local -- chmod 700 /tmp/sonda >/dev/null 2>&1; then
  echo "ERROR SUSTRATO_PERFIL_IGNORADO: el perfil Localhost de sonda prohibe la familia chmod con SCMP_ACT_ERRNO y aun asi el chmod funciono dentro del contenedor. El kubelet acepto el campo y el runtime no cargo el filtro. Revise: kubectl --kubeconfig $KC -n sonda-p03 exec sonda-local -- grep Seccomp /proc/1/status"
  exit 1
fi
echo "prueba de sustrato 2 OK: un perfil Localhost en el disco del nodo llega al contenedor y bloquea lo que dice bloquear."
docker exec "$NODO" rm -f /var/lib/kubelet/seccomp/profiles/sonda.json

# ---------- prueba de sustrato 3: AppArmor queda en enforce sobre el proceso ----------
docker exec "$NODO" sh -c 'mkdir -p /etc/apparmor.d/cks && cat > /etc/apparmor.d/cks/sonda <<PERFIL
#include <tunables/global>

profile cks-p03-sonda flags=(attach_disconnected) {
  #include <abstractions/base>

  file,

  deny /** w,
}
PERFIL
apparmor_parser -q -r /etc/apparmor.d/cks/sonda' || {
  echo "ERROR SUSTRATO_PARSER_NO_CARGA: apparmor_parser no pudo cargar el perfil de sonda dentro del nodo. Sin perfil cargado en el kernel, containerd rechaza el Pod con 'apparmor profile not found'. Revise: docker exec $NODO apparmor_parser -r /etc/apparmor.d/cks/sonda"
  exit 1
}
kubectl --kubeconfig "$KC" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: sonda-apparmor
  namespace: sonda-p03
spec:
  containers:
  - name: c
    image: $BB
    command: ["sh","-c","sleep 900"]
    securityContext:
      appArmorProfile:
        type: Localhost
        localhostProfile: cks-p03-sonda
YAML
if ! kubectl --kubeconfig "$KC" -n sonda-p03 wait --for=condition=Ready pod/sonda-apparmor --timeout=120s >/dev/null 2>&1; then
  RAZON=$(kubectl --kubeconfig "$KC" -n sonda-p03 get pod sonda-apparmor -o jsonpath='{.status.reason}: {.status.message}{.status.containerStatuses[0].state.waiting.reason}: {.status.containerStatuses[0].state.waiting.message}' 2>/dev/null || true)
  echo "ERROR SUSTRATO_SIN_APPARMOR_EN_EL_NODO: el Pod de sonda con appArmorProfile no llego a Ready. Lo que reporto el nodo fue: $RAZON. Si dice 'AppArmor is not enabled on the host', al kubelet le falta ver /sys/kernel/security/apparmor. Si dice 'apparmor is not supported', containerd hizo su chequeo antes de que securityfs estuviera montado y hay que reiniciarlo: docker exec $NODO systemctl restart containerd. El Paso 3 depende por completo de esta cadena."
  docker exec "$NODO" sh -c 'printf "%s" "cks-p03-sonda" > /sys/kernel/security/apparmor/.remove' 2>/dev/null
  exit 1
fi
PERFIL_VIVO=$(kubectl --kubeconfig "$KC" -n sonda-p03 exec sonda-apparmor -- cat /proc/1/attr/current 2>/dev/null | tr -d '\0\n' || true)
if [ "$PERFIL_VIVO" != "cks-p03-sonda (enforce)" ]; then
  echo "ERROR SUSTRATO_APPARMOR_SIN_ENFORCE: el proceso 1 del contenedor de sonda reporta '$PERFIL_VIVO' en vez de 'cks-p03-sonda (enforce)'. Un perfil aceptado pero no aplicado no bloquea nada y el Paso 3 no significaria nada."
  docker exec "$NODO" sh -c 'printf "%s" "cks-p03-sonda" > /sys/kernel/security/apparmor/.remove' 2>/dev/null
  exit 1
fi
if kubectl --kubeconfig "$KC" -n sonda-p03 exec sonda-apparmor -- touch /tmp/sonda >/dev/null 2>&1; then
  echo "ERROR SUSTRATO_APPARMOR_NO_NIEGA: el perfil de sonda dice deny /** w y aun asi se pudo crear un archivo dentro del contenedor. Revise el perfil cargado: docker exec $NODO grep cks-p03 /sys/kernel/security/apparmor/profiles"
  docker exec "$NODO" sh -c 'printf "%s" "cks-p03-sonda" > /sys/kernel/security/apparmor/.remove' 2>/dev/null
  exit 1
fi
kubectl --kubeconfig "$KC" -n sonda-p03 exec sonda-apparmor -- cat /etc/hostname >/dev/null 2>&1 || {
  echo "ERROR SUSTRATO_APPARMOR_DEMASIADO_ESTRECHO: el perfil de sonda tambien impidio leer /etc/hostname. Un perfil de deny-write tiene que dejar leer, o el Paso 3 no podria distinguir un perfil correcto de un contenedor roto."
  docker exec "$NODO" sh -c 'printf "%s" "cks-p03-sonda" > /sys/kernel/security/apparmor/.remove' 2>/dev/null
  exit 1
}
echo "prueba de sustrato 3 OK: AppArmor queda en enforce sobre el proceso, niega la escritura y deja leer."
docker exec "$NODO" sh -c 'printf "%s" "cks-p03-sonda" > /sys/kernel/security/apparmor/.remove; rm -f /etc/apparmor.d/cks/sonda'

kubectl --kubeconfig "$KC" delete namespace sonda-p03 --wait=false >/dev/null 2>&1

# ---------- el conjunto ----------
kubectl --kubeconfig "$KC" get namespace conjunto >/dev/null 2>&1 || \
  kubectl --kubeconfig "$KC" create namespace conjunto >/dev/null

kubectl --kubeconfig "$KC" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: celaduria-sin-uniforme
  namespace: conjunto
spec:
  securityContext:
    seccompProfile:
      type: Unconfined
  containers:
  - name: celador
    image: $BB
    command: ["sh","-c","sleep 86400"]
YAML
kubectl --kubeconfig "$KC" -n conjunto wait --for=condition=Ready pod/celaduria-sin-uniforme --timeout=180s >/dev/null

# ---------- la salida trasera del patio ----------
# Carga deliberada y determinista, entregada en base64 a proposito: es una venda
# de cortesia, no un escondite de verdad, y la respuesta esta al final del laboratorio.
echo 'Y2F0ID4gL2V0Yy9zeXN0ZW1kL3N5c3RlbS9tYW50ZW5pbWllbnRvLXJlbW90by5zb2NrZXQgPDwnRU9GJwpbVW5pdF0KRGVzY3JpcHRpb249TWFudGVuaW1pZW50byByZW1vdG8gZGVsIGNvbmp1bnRvCltTb2NrZXRdCkxpc3RlblN0cmVhbT0zNDUyMQpBY2NlcHQ9bm8KW0luc3RhbGxdCldhbnRlZEJ5PXNvY2tldHMudGFyZ2V0CkVPRgpjYXQgPiAvZXRjL3N5c3RlbWQvc3lzdGVtL21hbnRlbmltaWVudG8tcmVtb3RvLnNlcnZpY2UgPDwnRU9GJwpbVW5pdF0KRGVzY3JpcHRpb249TWFudGVuaW1pZW50byByZW1vdG8gZGVsIGNvbmp1bnRvCltTZXJ2aWNlXQpFeGVjU3RhcnQ9L2Jpbi9zbGVlcCBpbmZpbml0eQpFT0YKc3lzdGVtY3RsIGRhZW1vbi1yZWxvYWQKc3lzdGVtY3RsIGVuYWJsZSAtLW5vdyBtYW50ZW5pbWllbnRvLXJlbW90by5zb2NrZXQgPi9kZXYvbnVsbCAyPiYxCg==' \
  | base64 -d | docker exec -i "$NODO" sh
sleep 2
SOBRA=$(docker exec "$NODO" ss -H -lnt 2>/dev/null | awk '{n=split($4,p,":"); port=p[n]; addr=substr($4,1,length($4)-length(port)-1); if (addr !~ /^127\./ && addr != "[::1]") print port}' | grep -vxE '2379|2380|6443|10250|10256' | head -1 || true)
if [ -z "$SOBRA" ]; then
  echo "ERROR SUSTRATO_SIN_PUERTO_SOBRANTE: el setup planto un servicio que deberia dejar un puerto de mas escuchando en el nodo y ss no lo ve. Sin el, el Paso 4 no tendria nada que encontrar. Revise a mano: docker exec $NODO ss -lntp"
  exit 1
fi
echo "prueba de sustrato 4 OK: el nodo tiene un puerto de mas escuchando en una direccion no loopback."

echo "espacio de trabajo listo en $W"
echo "cluster cks-p03 con kubeconfig privado en $KC"
echo "namespace de trabajo: conjunto"
echo "nodo (contenedor de docker): $NODO"
kubectl --kubeconfig "$KC" -n conjunto get pods
echo "el celador sin uniforme ya esta puesto y es el caso de referencia del Paso 1: no lo borre ni lo vista."
