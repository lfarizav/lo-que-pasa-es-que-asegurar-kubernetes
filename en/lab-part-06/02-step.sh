#!/usr/bin/env bash
# lab-part-06 step 2 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

W="$HOME/cks-lab/p06"; K="kubectl --kubeconfig $W/kubeconfig"

# 1. La pelicula completa del namespace, en orden, una linea por evento.
"$W/bin/minuta" | jq -r 'select(.objectRef.namespace=="la-bodega")
  | [.requestReceivedTimestamp, .user.username, .verb, .objectRef.resource,
     (.objectRef.subresource // "-"), (.objectRef.name // "-"),
     .level, (.responseStatus.code|tostring)] | @tsv' | column -t

# 2. Quien toco el Secret y con que resultado cada vez.
"$W/bin/minuta" | jq -r 'select(.objectRef.resource=="secrets" and .objectRef.name=="la-caja-fuerte")
  | [.requestReceivedTimestamp, .user.username, .verb, (.responseStatus.code|tostring)] | @tsv'

# 3. Que le dieron y cuando: el permiso que cambio el 403 en 200.
"$W/bin/minuta" | jq -r 'select(.objectRef.resource=="rolebindings" and .verb=="create")
  | [.requestReceivedTimestamp, .objectRef.name] | @tsv'
$K -n la-bodega get rolebinding prestamo-de-llaves -o yaml | head -20

# 4. Lo que de verdad se llevaron: con nivel RequestResponse el cuerpo del
#    Secret queda escrito en la propia bitacora.
"$W/bin/minuta" | jq -r 'select(.objectRef.name=="la-caja-fuerte" and .verb=="get"
  and .responseStatus.code==200) | .responseObject.data.clave' | head -1 | base64 -d; echo

# 5. Contener sin destruir la evidencia: se revoca el permiso, NO la cuenta.
$K -n la-bodega delete rolebinding prestamo-de-llaves
$K auth can-i get secrets -n la-bodega \
  --as=system:serviceaccount:la-bodega:auxiliar-de-turno

# 6. Rotar lo que ya quedo escrito para siempre en la bitacora.
$K -n la-bodega create secret generic la-caja-fuerte \
  --from-literal=clave=combinacion-9042-rotada --dry-run=client -o yaml | $K apply -f -

# The answer file the lab asks you to type, written from the live audit log:
M=$("$W/bin/minuta")
LECTOR=$(echo "$M" | jq -r 'select(.objectRef.name=="la-caja-fuerte" and .verb=="get" and .responseStatus.code==200) | .user.username' | head -1)
T403=$(echo "$M" | jq -r --arg u "$LECTOR" 'select(.objectRef.name=="la-caja-fuerte" and .user.username==$u and .responseStatus.code==403) | .requestReceivedTimestamp' | head -1)
T200=$(echo "$M" | jq -r --arg u "$LECTOR" 'select(.objectRef.name=="la-caja-fuerte" and .user.username==$u and .responseStatus.code==200) | .requestReceivedTimestamp' | head -1)
cat > "$W/02-respuesta.txt" <<RESP
CUENTA=$LECTOR
SECRETO=la-caja-fuerte
CODIGO_PRIMER_INTENTO=$(echo "$M" | jq -r --arg u "$LECTOR" 'select(.objectRef.name=="la-caja-fuerte" and .user.username==$u) | .responseStatus.code' | head -1)
ROLEBINDING=$(echo "$M" | jq -r --arg a "$T403" --arg b "$T200" 'select(.objectRef.resource=="rolebindings" and .verb=="create" and .objectRef.namespace=="la-bodega" and .requestReceivedTimestamp > $a and .requestReceivedTimestamp < $b) | .objectRef.name' | head -1)
VALOR_FILTRADO=$(echo "$M" | jq -r 'select(.objectRef.name=="la-caja-fuerte" and .verb=="get" and .responseStatus.code==200) | .responseObject.data.clave' | head -1 | base64 -d)
RESP
cat "$W/02-respuesta.txt"
