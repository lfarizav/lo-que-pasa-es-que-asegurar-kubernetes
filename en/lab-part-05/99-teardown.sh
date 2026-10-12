#!/usr/bin/env bash
# lab-part-05 - teardown
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

kind delete cluster --name cks-p05 --kubeconfig ~/cks-lab/p05/kubeconfig

docker rm -f cks-p05-registry cks-p05-probe >/dev/null 2>&1
docker image rm -f la-tienda:bodega la-tienda:flaca >/dev/null 2>&1
docker image rm -f 127.0.0.1:5065/tienda/pan:v1 \
  127.0.0.1:5065/tienda/proveedor-a:2026-08 \
  127.0.0.1:5065/tienda/proveedor-b:2026-08 >/dev/null 2>&1

rm -rf ~/cks-lab/p05

echo "cluster cks-p05, registro y llaves eliminados; el workspace p05 borrado"
echo "sus otros clusteres de kind siguen intactos:"
kind get clusters
