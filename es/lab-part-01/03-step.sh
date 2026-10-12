#!/usr/bin/env bash
# lab-part-01 step 3 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/cks-lab/p01
K="kubectl --kubeconfig $HOME/cks-lab/p01/kubeconfig"

# 1. La cedula: certificado autofirmado con el nombre de la porteria adentro,
#    tanto en el CN como en el SAN. Sin SAN, los clientes modernos no lo aceptan.
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout cedula.key -out cedula.crt \
  -subj "/CN=laporteria.local/O=conjunto-la-esperanza" \
  -addext "subjectAltName=DNS:laporteria.local"
openssl x509 -in cedula.crt -noout -subject -ext subjectAltName -fingerprint -sha256

# 2. La cedula guardada donde el controlador la busca: un Secret de tipo TLS.
$K -n la-porteria create secret tls cedula-de-la-porteria \
  --cert=cedula.crt --key=cedula.key
$K -n la-porteria get secret cedula-de-la-porteria -o jsonpath='{.type}{"\n"}'

# 3. La entrada, con bloque tls apuntando a ese Secret.
cat > entrada-tls.yaml <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: la-entrada-con-cedula
  namespace: la-porteria
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - laporteria.local
    secretName: cedula-de-la-porteria
  rules:
  - host: laporteria.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: citofono
            port:
              number: 80
YAML
$K apply -f entrada-tls.yaml
$K -n la-porteria get ingress la-entrada-con-cedula

# 4. El controlador no recarga sus reglas en el mismo instante del apply.
echo "esperando a que el controlador cargue la entrada nueva..."
for _ in $(seq 1 30); do
  CODIGO=$(curl -sSk -o /dev/null -w '%{http_code}' --max-time 10 \
    --resolve laporteria.local:8449:127.0.0.1 https://laporteria.local:8449/ 2>/dev/null)
  [ "$CODIGO" = "200" ] && break
  sleep 2
done
echo "codigo https: $CODIGO"
curl -sSk --resolve laporteria.local:8449:127.0.0.1 https://laporteria.local:8449/

# 5. LA PRUEBA QUE CASI NADIE HACE: de quien es la cedula que estan sirviendo.
echo "--- huella del certificado que USTED guardo ---"
openssl x509 -in cedula.crt -noout -fingerprint -sha256
echo "--- huella del certificado que la ENTRADA esta sirviendo ---"
openssl s_client -connect 127.0.0.1:8449 -servername laporteria.local </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -fingerprint -sha256

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/cks-lab/p01"
cat > "$D/03-respuesta.txt" <<RESP
HUELLA_DE_MI_CERTIFICADO=$(openssl x509 -in cedula.crt -noout -fingerprint -sha256 | cut -d= -f2)
HUELLA_SERVIDA_POR_LA_ENTRADA=$(openssl s_client -connect 127.0.0.1:8449 -servername laporteria.local </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256 | cut -d= -f2)
CODIGO_HTTPS=$(curl -sSk -o /dev/null -w '%{http_code}' --max-time 10 --resolve laporteria.local:8449:127.0.0.1 https://laporteria.local:8449/)
RESP
cat "$D/03-respuesta.txt"
