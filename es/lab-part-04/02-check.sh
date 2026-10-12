#!/usr/bin/env bash
# lab-part-04 step 2 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
KC="$HOME/cks-lab/p04/kubeconfig"
D="$HOME/cks-lab/p04"
NODO="cks-p04-control-plane"
ETCDF="--endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"
test -f "$D/02-respuesta.txt" || exit 1

VALOR=$(kubectl --kubeconfig "$KC" -n tienda get secret caja-fuerte -o jsonpath='{.data.clave}' 2>/dev/null | base64 -d 2>/dev/null)
test "$VALOR" = "la-plata-de-la-tienda-2026" || exit 1
VALORCM=$(kubectl --kubeconfig "$KC" -n tienda get configmap aviso-de-la-tienda -o jsonpath='{.data.clave}' 2>/dev/null)
test "$VALORCM" = "la-plata-de-la-tienda-2026" || exit 1

docker exec "$NODO" grep -q -- "--encryption-provider-config=" /etc/kubernetes/manifests/kube-apiserver.yaml || exit 1
PRIMERO=$(docker exec "$NODO" sh -c "sed -n '/providers:/,\$p' /etc/kubernetes/enc/enc.yaml | grep -m1 -oE '^ *- [a-z]+' | tr -d ' -'" 2>/dev/null)
test "$PRIMERO" != "identity" || exit 1
test -n "$PRIMERO" || exit 1

docker exec "$NODO" test -x /usr/local/bin/etcdctl || {
  ETCD_IMG=$(docker exec "$NODO" grep -m1 'image:' /etc/kubernetes/manifests/etcd.yaml | awk '{print $2}')
  docker exec "$NODO" sh -c "mkdir -p /mnt/imagen-de-etcd && ctr -n k8s.io images mount $ETCD_IMG /mnt/imagen-de-etcd >/dev/null && cp /mnt/imagen-de-etcd/usr/local/bin/etcdctl /usr/local/bin/etcdctl && chmod +x /usr/local/bin/etcdctl && ctr -n k8s.io images unmount /mnt/imagen-de-etcd >/dev/null" || exit 1
}

CRUDO=$(docker exec "$NODO" sh -c "etcdctl $ETCDF get /registry/secrets/tienda/caja-fuerte" 2>/dev/null | tr -d '\0')
echo "$CRUDO" | grep -qa 'k8s:enc:' || exit 1
echo "$CRUDO" | grep -qa 'la-plata-de-la-tienda-2026' && exit 1

CRUDOCM=$(docker exec "$NODO" sh -c "etcdctl $ETCDF get /registry/configmaps/tienda/aviso-de-la-tienda" 2>/dev/null | tr -d '\0')
echo "$CRUDOCM" | grep -qa 'la-plata-de-la-tienda-2026' || exit 1

kubectl --kubeconfig "$KC" -n tienda delete secret sonda-de-calificacion --ignore-not-found >/dev/null 2>&1
kubectl --kubeconfig "$KC" -n tienda create secret generic sonda-de-calificacion \
  --from-literal=clave='SONDA-DE-CALIFICACION-EN-CLARO' >/dev/null 2>&1 || exit 1
SONDA=$(docker exec "$NODO" sh -c "etcdctl $ETCDF get /registry/secrets/tienda/sonda-de-calificacion" 2>/dev/null | tr -d '\0')
kubectl --kubeconfig "$KC" -n tienda delete secret sonda-de-calificacion --ignore-not-found >/dev/null 2>&1
echo "$SONDA" | grep -qa 'k8s:enc:' || exit 1
echo "$SONDA" | grep -qa 'SONDA-DE-CALIFICACION-EN-CLARO' && exit 1

PREFIJO=$(echo "$CRUDO" | grep -oa 'k8s:enc:[a-z0-9]*:v1:[a-z0-9-]*:' | head -1)
test -n "$PREFIJO" || exit 1

grep -qxF "SECRETO_CIFRADO_EN_ETCD=true" "$D/02-respuesta.txt" || exit 1
grep -qxF "CONFIGMAP_EN_CLARO_EN_ETCD=true" "$D/02-respuesta.txt" || exit 1
grep -qxF "PREFIJO_DEL_PROVEEDOR=$PREFIJO" "$D/02-respuesta.txt" || exit 1
echo ok
