#!/usr/bin/env bash
# lab-part-01 step 2 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/cks-lab/p01
K="kubectl --kubeconfig $HOME/cks-lab/p01/kubeconfig"
NODO=$($K get nodes -o jsonpath='{.items[0].metadata.name}')
echo "el nodo se llama $NODO"

# 1. La requisa. El manifiesto ya viene fijado por digest desde el setup.
$K delete job kube-bench --ignore-not-found --wait=true
$K apply -f kube-bench-job.yaml
$K wait --for=condition=complete job/kube-bench --timeout=300s
$K logs job/kube-bench > informe-antes.txt

# 2. Leer el informe: que fallo, y cuantos fallaron.
grep -E '^\[FAIL\]' informe-antes.txt
awk '/^== Summary total ==/{f=1} f && /checks FAIL/{print $1" checks FAIL"; exit}' informe-antes.txt

# 3. Escoger UNO de los cuatro arreglables y arreglarlo. Aqui se escoge 1.4.1,
#    el --profiling del kube-scheduler, que es el de menor riesgo.
#    El nodo de kind NO tiene vi ni nano: se edita con sed desde afuera.
docker exec "$NODO" grep -n "leader-elect" /etc/kubernetes/manifests/kube-scheduler.yaml
docker exec "$NODO" sed -i \
  's|^    - --leader-elect=true$|    - --leader-elect=true\n    - --profiling=false|' \
  /etc/kubernetes/manifests/kube-scheduler.yaml
docker exec "$NODO" grep -n "profiling" /etc/kubernetes/manifests/kube-scheduler.yaml

# 4. El kubelet ve el archivo cambiado y vuelve a crear el pod estatico solo.
#    Espere a que el proceso vivo traiga la bandera nueva antes de recalificar.
echo "esperando a que el kube-scheduler vuelva con la bandera nueva..."
for _ in $(seq 1 30); do
  $K -n kube-system get pod "kube-scheduler-$NODO" -o jsonpath='{.spec.containers[0].command}' 2>/dev/null \
    | grep -qF '"--profiling=false"' && break
  sleep 5
done
$K -n kube-system wait --for=condition=Ready pod/kube-scheduler-$NODO --timeout=180s
$K -n kube-system get pods -l tier=control-plane
$K get nodes

# 5. La requisa otra vez.
$K delete job kube-bench --ignore-not-found --wait=true
$K apply -f kube-bench-job.yaml
$K wait --for=condition=complete job/kube-bench --timeout=300s
$K logs job/kube-bench > informe-despues.txt
grep -E '^\[(PASS|FAIL)\] 1\.4\.1 ' informe-despues.txt
awk '/^== Summary total ==/{f=1} f && /checks FAIL/{print $1" checks FAIL"; exit}' informe-despues.txt

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/cks-lab/p01"
cat > "$D/02-respuesta.txt" <<RESP
CONTROL_ARREGLADO=1.4.1
FALLAS_ANTES=$(awk '/^== Summary total ==/{f=1} f && /checks FAIL/{print $1; exit}' informe-antes.txt)
FALLAS_DESPUES=$(awk '/^== Summary total ==/{f=1} f && /checks FAIL/{print $1; exit}' informe-despues.txt)
RESP
cat "$D/02-respuesta.txt"
