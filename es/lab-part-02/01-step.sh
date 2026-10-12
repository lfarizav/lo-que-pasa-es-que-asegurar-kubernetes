#!/usr/bin/env bash
# lab-part-02 step 1 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

KC="$HOME/cks-lab/p02/kubeconfig"
K="kubectl --kubeconfig $KC"
cd ~/cks-lab/p02

$K -n porteria get rolebinding llave-maestra-del-celador -o yaml | sed -n '/^roleRef:/,/^subjects:/p'
$K -n porteria delete rolebinding llave-maestra-del-celador

$K -n porteria create role puesto-de-vigilancia --verb=get,list,watch --resource=pods
$K -n porteria patch role puesto-de-vigilancia --type=json \
  -p '[{"op":"add","path":"/rules/-","value":{"apiGroups":[""],"resources":["configmaps"],"verbs":["get","list"]}}]'
$K -n porteria create rolebinding el-celador-solo-mira \
  --role=puesto-de-vigilancia --serviceaccount=porteria:celador-de-turno

CARNE="system:serviceaccount:porteria:celador-de-turno"
for PERMISO in "list pods" "watch pods" "get configmaps" "watch configmaps" \
               "delete pods" "get secrets" "create pods"; do
  printf '%-24s -> ' "$PERMISO"
  $K auth can-i $PERMISO -n porteria --as="$CARNE"
done
printf '%-24s -> ' "list pods en kube-system"
$K auth can-i list pods -n kube-system --as="$CARNE"
printf '%-24s -> ' "todo en todos lados"
$K auth can-i '*' '*' --all-namespaces --as="$CARNE"

# calentar el resolvedor: la primera consulta de DNS de un contenedor recien creado puede perderse
$K -n porteria exec garita -- sh -c \
  'wget -q -T 5 -O /dev/null --no-check-certificate https://kubernetes.default.svc/version 2>/dev/null; true'

$K -n porteria exec garita -- sh -c '
T=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
for RUTA in "api/v1/namespaces/$NS/pods" \
            "api/v1/namespaces/$NS/configmaps/turnos-del-mes" \
            "api/v1/namespaces/$NS/secrets/clave-de-la-reja"; do
  printf "%-52s -> " "/$RUTA"
  for i in 1 2 3; do
    C=$(wget -q -S -T 10 -O /dev/null --no-check-certificate \
      --header="Authorization: Bearer $T" "https://kubernetes.default.svc/$RUTA" 2>&1 \
      | grep -m1 -oE "HTTP/1.1 [0-9]+")
    [ -n "$C" ] && break; sleep 2
  done
  echo "$C"
done'
# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/cks-lab/p02"
CODIGO=$($K -n porteria exec garita -- sh -c 'T=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token); wget -q -S -O /dev/null --no-check-certificate --header="Authorization: Bearer $T" https://kubernetes.default.svc/api/v1/namespaces/porteria/secrets/clave-de-la-reja 2>&1 | grep -m1 -oE "HTTP/1.1 [0-9]+" | cut -d" " -f2')
cat > "$D/01-respuesta.txt" <<RESP
CUENTA_DE_LA_GARITA=$($K -n porteria get pod garita -o jsonpath='{.spec.serviceAccountName}')
PUEDE_LISTAR_PODS=$($K auth can-i list pods -n porteria --as="$CARNE")
PUEDE_BORRAR_PODS=$($K auth can-i delete pods -n porteria --as="$CARNE")
PUEDE_LEER_SECRETS=$($K auth can-i get secrets -n porteria --as="$CARNE")
CODIGO_EN_LOS_SECRETS=$CODIGO
RESP
cat "$D/01-respuesta.txt"
