#!/usr/bin/env bash
# lab-part-04 step 2 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

KC="$HOME/cks-lab/p04/kubeconfig"
NODO="cks-p04-control-plane"
cd ~/cks-lab/p04

kubectl --kubeconfig "$KC" -n tienda create secret generic caja-fuerte \
  --from-literal=clave='la-plata-de-la-tienda-2026'
kubectl --kubeconfig "$KC" -n tienda create configmap aviso-de-la-tienda \
  --from-literal=clave='la-plata-de-la-tienda-2026'

docker exec "$NODO" grep -n encryption-provider-config /etc/kubernetes/manifests/kube-apiserver.yaml
docker exec "$NODO" cat /etc/kubernetes/enc/enc.yaml

ETCDF="--endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"

docker exec "$NODO" sh -c "etcdctl $ETCDF get /registry/secrets/tienda/caja-fuerte" | cat -v
docker exec "$NODO" sh -c "etcdctl $ETCDF get /registry/configmaps/tienda/aviso-de-la-tienda" | cat -v

docker exec "$NODO" sh -c "etcdctl $ETCDF get /registry/secrets/tienda/caja-fuerte" \
  | grep -oa 'k8s:enc:[a-z0-9]*:v1:[a-z0-9-]*:'
docker exec "$NODO" sh -c "etcdctl $ETCDF get /registry/secrets/tienda/caja-fuerte" \
  | grep -ca 'la-plata-de-la-tienda-2026'
docker exec "$NODO" sh -c "etcdctl $ETCDF get /registry/configmaps/tienda/aviso-de-la-tienda" \
  | grep -ca 'la-plata-de-la-tienda-2026'
# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/cks-lab/p04"
N_SEC=$(docker exec "$NODO" sh -c "etcdctl $ETCDF get /registry/secrets/tienda/caja-fuerte" | grep -ca 'la-plata-de-la-tienda-2026' || true)
N_CM=$(docker exec "$NODO" sh -c "etcdctl $ETCDF get /registry/configmaps/tienda/aviso-de-la-tienda" | grep -ca 'la-plata-de-la-tienda-2026' || true)
[ "$N_SEC" = 0 ] && CIF=true || CIF=false
[ "$N_CM" != 0 ] && CLARO=true || CLARO=false
cat > "$D/02-respuesta.txt" <<RESP
SECRETO_CIFRADO_EN_ETCD=$CIF
CONFIGMAP_EN_CLARO_EN_ETCD=$CLARO
PREFIJO_DEL_PROVEEDOR=$(docker exec "$NODO" sh -c "etcdctl $ETCDF get /registry/secrets/tienda/caja-fuerte" | grep -oa 'k8s:enc:[a-z0-9]*:v1:[a-z0-9-]*:' | head -1)
RESP
cat "$D/02-respuesta.txt"
