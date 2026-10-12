#!/usr/bin/env bash
# lab-part-03 step 4 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

KC="$HOME/cks-lab/p03/kubeconfig"
NODO="cks-p03-control-plane"
cd ~/cks-lab/p03

docker exec "$NODO" ss -lntp

docker exec "$NODO" ss -H -lnt \
  | awk '{n=split($4,p,":"); port=p[n]; addr=substr($4,1,length($4)-length(port)-1); if (addr !~ /^127\./) print addr" "port}'

docker exec "$NODO" systemctl list-sockets --no-pager
docker exec "$NODO" systemctl list-unit-files --type=socket --no-pager | grep -w enabled

docker exec "$NODO" systemctl disable --now mantenimiento-remoto.socket
docker exec "$NODO" sh -c 'rm -f /etc/systemd/system/mantenimiento-remoto.socket /etc/systemd/system/mantenimiento-remoto.service && systemctl daemon-reload'

docker exec "$NODO" ss -lntp
docker exec "$NODO" systemctl is-active kubelet
docker exec "$NODO" curl -s -o /dev/null -w "kubelet_healthz=%{http_code}\n" http://127.0.0.1:10248/healthz
kubectl --kubeconfig "$KC" get nodes

# The answer file the lab asks you to type: one line per control plane port, with the
# process name read from the live node and a justification.
D="$HOME/cks-lab/p03"
proc() { docker exec "$NODO" ss -H -lntp "sport = :$1" | grep -oE 'users:\(\("[^"]+' | head -1 | cut -d'"' -f2; }
cat > "$D/04-respuesta.txt" <<RESP
2379|$(proc 2379)|Es la base de datos del cluster; la usan el API server y solo el.
2380|$(proc 2380)|Es el puerto por donde los miembros de etcd se hablan entre si.
6443|$(proc 6443)|Es la unica puerta de entrada a la API del cluster y la usan kubectl y todos los nodos.
10250|$(proc 10250)|Es la API del kubelet, por donde el API server pide logs, exec y metricas del nodo.
10256|$(proc 10256)|Es el chequeo de salud de kube-proxy que usan los balanceadores externos.
10257|$(proc 10257)|Es el puerto seguro del controller-manager para salud y metricas.
10259|$(proc 10259)|Es el puerto seguro del scheduler para salud y metricas.
RESP
cat "$D/04-respuesta.txt"
