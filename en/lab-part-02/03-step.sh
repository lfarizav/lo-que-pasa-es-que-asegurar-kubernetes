#!/usr/bin/env bash
# lab-part-02 step 3 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

KC="$HOME/cks-lab/p02/kubeconfig"
K="kubectl --kubeconfig $KC"
NODO="cks-p02-control-plane"
cd ~/cks-lab/p02

docker exec "$NODO" sh -c \
  'curl -sk -o /dev/null -w "sin_credenciales=%{http_code}\n" https://127.0.0.1:10250/pods'
$K get --raw /api/v1/nodes/$NODO/proxy/configz | tr ',' '\n' | grep -iE 'anonymous|"authorization"'
docker exec "$NODO" sh -c 'tr "\0" "\n" < /proc/$(pgrep -x kubelet)/cmdline | grep -- --config'

docker exec "$NODO" sh -c '
sed -i "/^  anonymous:/{n;s/enabled: true/enabled: false/}" /var/lib/kubelet/config.yaml
sed -i "s/^  mode: AlwaysAllow\$/  mode: Webhook/" /var/lib/kubelet/config.yaml
systemctl restart kubelet'

$K wait --for=condition=Ready node/$NODO --timeout=180s
$K -n porteria wait --for=condition=Ready pod/garita --timeout=180s
$K -n porteria wait --for=condition=Ready pod/ronda-nocturna --timeout=180s

docker exec "$NODO" sh -c \
  'curl -sk -o /dev/null -w "sin_credenciales=%{http_code}\n" https://127.0.0.1:10250/pods'
docker exec "$NODO" sh -c \
  'curl -s -o /dev/null -w "puerto_de_solo_lectura=%{http_code}\n" --max-time 5 http://127.0.0.1:10255/pods'
$K get --raw /api/v1/nodes/$NODO/proxy/configz | tr ',' '\n' | grep -iE 'anonymous|"authorization"'
for i in $(seq 1 10); do
  $K -n porteria exec garita -- echo "el API server sigue llegando al kubelet" && break
  sleep 6
done
# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/cks-lab/p02"
CFG=$($K get --raw /api/v1/nodes/$NODO/proxy/configz)
cat > "$D/03-respuesta.txt" <<RESP
CODIGO_SIN_CREDENCIALES=$(docker exec "$NODO" sh -c 'curl -sk -o /dev/null -w "%{http_code}" https://127.0.0.1:10250/pods')
ANONIMO_HABILITADO=$(echo "$CFG" | jq -r '.kubeletconfig.authentication.anonymous.enabled')
MODO_DE_AUTORIZACION=$(echo "$CFG" | jq -r '.kubeletconfig.authorization.mode')
ARCHIVO_DE_CONFIGURACION=$(docker exec "$NODO" sh -c 'tr "\0" "\n" < /proc/$(pgrep -x kubelet)/cmdline | grep -- --config= | cut -d= -f2')
RESP
cat "$D/03-respuesta.txt"
