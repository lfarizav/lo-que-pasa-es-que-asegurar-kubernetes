#!/usr/bin/env bash
# lab-part-05 step 1 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/cks-lab/p05/la-tienda
LAB="$HOME/cks-lab/p05"

cat Dockerfile.bodega
cat tienda.go
docker image inspect la-tienda:bodega -f '{{.Size}}'

cat > Dockerfile.flaca <<'DOCKER'
FROM golang:1.25@sha256:fe5d57d3b718e7a4986bae156c2d73f44973bfd313073aed08a4de6692bb6161 AS constructor
WORKDIR /src
COPY tienda.go .
RUN go mod init tienda
ENV CGO_ENABLED=0
RUN go build -ldflags="-s -w" -o /tienda ./tienda.go

FROM scratch
COPY --from=constructor /tienda /tienda
EXPOSE 8080
CMD ["/tienda"]
DOCKER

docker build -t la-tienda:flaca -f Dockerfile.flaca .

GORDA=$(docker image inspect la-tienda:bodega -f '{{.Size}}')
FLACA=$(docker image inspect la-tienda:flaca  -f '{{.Size}}')
echo "bodega=$GORDA flaca=$FLACA"

docker rm -f cks-p05-probe >/dev/null 2>&1
docker run -d --name cks-p05-probe la-tienda:flaca
sleep 2
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' cks-p05-probe)
curl -s "http://$IP:8080/"
curl -s "http://$IP:8080/version"
CARTA=$(curl -s "http://$IP:8080/" | tr -d '\r' | head -1)
GOVER=$(curl -s "http://$IP:8080/version" | tr -d '\r' | head -1)
docker rm -f cks-p05-probe

printf 'TAMANO_BODEGA=%s\nTAMANO_FLACA=%s\nCARTA_QUE_SIRVE=%s\nVERSION_DE_GO=%s\n' \
  "$GORDA" "$FLACA" "$CARTA" "$GOVER" > "$LAB/01-respuesta.txt"
cat "$LAB/01-respuesta.txt"
