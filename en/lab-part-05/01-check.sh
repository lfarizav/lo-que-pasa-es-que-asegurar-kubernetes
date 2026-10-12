#!/usr/bin/env bash
# lab-part-05 step 1 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/cks-lab/p05"
LIMITE=26214400
test -f "$D/01-respuesta.txt" || exit 1
docker image inspect la-tienda:flaca >/dev/null 2>&1 || exit 1
docker image inspect la-tienda:bodega >/dev/null 2>&1 || exit 1
FLACA=$(docker image inspect la-tienda:flaca -f '{{.Size}}' 2>/dev/null)
GORDA=$(docker image inspect la-tienda:bodega -f '{{.Size}}' 2>/dev/null)
echo "$FLACA" | grep -Eq '^[0-9]+$' || exit 1
echo "$GORDA" | grep -Eq '^[0-9]+$' || exit 1
test "$FLACA" -lt "$LIMITE" || exit 1
test "$GORDA" -gt "$FLACA" || exit 1
grep -qxF "TAMANO_BODEGA=$GORDA" "$D/01-respuesta.txt" || exit 1
grep -qxF "TAMANO_FLACA=$FLACA" "$D/01-respuesta.txt" || exit 1
CID=$(docker create la-tienda:flaca 2>/dev/null)
test -n "$CID" || exit 1
rm -f "$D/.chequeo-tienda.bin" "$D/.chequeo-go.bin"
if ! docker cp "$CID:/tienda" "$D/.chequeo-tienda.bin" >/dev/null 2>&1; then
  docker rm -f "$CID" >/dev/null 2>&1; exit 1
fi
if docker cp "$CID:/usr/local/go/bin/go" "$D/.chequeo-go.bin" >/dev/null 2>&1; then
  rm -f "$D/.chequeo-go.bin" "$D/.chequeo-tienda.bin"
  docker rm -f "$CID" >/dev/null 2>&1; exit 1
fi
docker rm -f "$CID" >/dev/null 2>&1
head -c 4 "$D/.chequeo-tienda.bin" | od -An -tx1 | tr -d ' \n' | grep -qx '7f454c46' || { rm -f "$D/.chequeo-tienda.bin"; exit 1; }
rm -f "$D/.chequeo-tienda.bin"
docker rm -f cks-p05-probe >/dev/null 2>&1
docker run -d --name cks-p05-probe la-tienda:flaca >/dev/null 2>&1 || exit 1
IP=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' cks-p05-probe 2>/dev/null)
  test -n "$IP" && curl -sf --max-time 3 "http://$IP:8080/" >/dev/null 2>&1 && break
  sleep 1
done
CARTA=$(curl -sf --max-time 5 "http://$IP:8080/" 2>/dev/null | tr -d '\r' | head -1)
GOVER=$(curl -sf --max-time 5 "http://$IP:8080/version" 2>/dev/null | tr -d '\r' | head -1)
docker rm -f cks-p05-probe >/dev/null 2>&1
test "$CARTA" = "pan-de-la-esquina-v1" || exit 1
echo "$GOVER" | grep -Eq '^go1\.[0-9]' || exit 1
grep -qxF "CARTA_QUE_SIRVE=$CARTA" "$D/01-respuesta.txt" || exit 1
grep -qxF "VERSION_DE_GO=$GOVER" "$D/01-respuesta.txt" || exit 1
echo ok
