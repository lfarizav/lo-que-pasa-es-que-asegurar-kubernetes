#!/usr/bin/env bash
# lab-part-06 step 4 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

W="$HOME/cks-lab/p06"; K="kubectl --kubeconfig $W/kubeconfig"

# 1. Que escribe la aplicacion hoy, antes de ponerle el candado.
$K -n el-local get deploy caja-registradora -o yaml | head -40
POD=$($K -n el-local get pod -l app=caja-registradora -o jsonpath='{.items[0].metadata.name}')
$K -n el-local exec "$POD" -- sh -c 'ls -l /www/index.html /var/log/local/ventas.log'

# 2. Poner el candado y, al mismo tiempo, los dos cajones de trabajo.
$K -n el-local patch deployment caja-registradora --type=strategic -p '
spec:
  template:
    spec:
      volumes:
      - name: sitio
        emptyDir: {}
      - name: bitacora
        emptyDir: {}
      containers:
      - name: caja
        securityContext:
          readOnlyRootFilesystem: true
        volumeMounts:
        - name: sitio
          mountPath: /www
        - name: bitacora
          mountPath: /var/log/local
'
$K -n el-local rollout status deployment/caja-registradora --timeout=240s

# 3. Comprobar desde adentro: los cajones escriben, el resto no.
POD=$($K -n el-local get pod -l app=caja-registradora -o jsonpath='{.items[0].metadata.name}')
$K -n el-local exec "$POD" -- sh -c 'touch /www/prueba && echo "www: escribe"'
$K -n el-local exec "$POD" -- sh -c 'touch /tmp/prueba 2>&1 || echo "tmp: de solo lectura, como debe ser"'
$K -n el-local exec "$POD" -- sh -c 'touch /prueba 2>&1 || echo "raiz: de solo lectura, como debe ser"'
$K -n el-local exec "$POD" -- sh -c 'cat /var/log/local/ventas.log'

# 4. El negocio sigue atendiendo por el Service.
$K -n el-local exec mandadero -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 8 \
  http://caja-registradora.el-local.svc.cluster.local/

# 5. Y el rastro que dejaron esos exec en la minuta del Paso 1.
sleep 3
"$W/bin/minuta" | jq -r 'select(.objectRef.namespace=="el-local" and .objectRef.subresource=="exec")
  | [.requestReceivedTimestamp, .user.username, .verb, .objectRef.resource,
     .objectRef.subresource, .objectRef.name, .level] | @tsv' | tail -5

# The answer file the lab asks you to type, written from the live audit log:
M=$("$W/bin/minuta" | jq -c 'select(.objectRef.namespace=="el-local" and .objectRef.subresource=="exec")')
ID=$(echo "$M" | tail -1 | jq -r .auditID)
cat > "$W/04-respuesta.txt" <<RESP
RECURSO=$(echo "$M" | tail -1 | jq -r .objectRef.resource)
SUBRECURSO=$(echo "$M" | tail -1 | jq -r .objectRef.subresource)
VERBO=$(echo "$M" | tail -1 | jq -r .verb)
NIVEL=$(echo "$M" | tail -1 | jq -r .level)
ETAPAS=$(echo "$M" | jq -r --arg id "$ID" 'select(.auditID==$id) | .stage' | paste -sd, -)
RESP
cat "$W/04-respuesta.txt"
