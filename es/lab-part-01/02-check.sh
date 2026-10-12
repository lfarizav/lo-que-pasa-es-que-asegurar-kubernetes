#!/usr/bin/env bash
# lab-part-01 step 2 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/cks-lab/p01"
K="kubectl --kubeconfig $D/kubeconfig"
T="$D/.calificacion"
test -f "$D/02-respuesta.txt" || exit 1
CTRL=$(grep -oP '(?<=CONTROL_ARREGLADO=).*' "$D/02-respuesta.txt")
case "$CTRL" in
  1.2.15|1.2.30|1.3.2|1.4.1) : ;;
  *) exit 1 ;;
esac
grep -qxF "FALLAS_ANTES=10" "$D/02-respuesta.txt" || exit 1
NODO=$($K get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
test -n "$NODO" || exit 1
$K get node "$NODO" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -qx True || exit 1
for C in kube-apiserver kube-controller-manager kube-scheduler etcd; do
  $K -n kube-system wait --for=condition=Ready pod "$C-$NODO" --timeout=120s >/dev/null 2>&1 || exit 1
done
case "$CTRL" in
  1.2.15) COMP=kube-apiserver;          BANDERA='--profiling=false' ;;
  1.2.30) COMP=kube-apiserver;          BANDERA='--service-account-extend-token-expiration=false' ;;
  1.3.2)  COMP=kube-controller-manager; BANDERA='--profiling=false' ;;
  1.4.1)  COMP=kube-scheduler;          BANDERA='--profiling=false' ;;
esac
$K -n kube-system get pod "$COMP-$NODO" -o jsonpath='{.spec.containers[0].command}' 2>/dev/null | grep -qF "\"$BANDERA\"" || exit 1
mkdir -p "$T" || exit 1
cat > "$T/kube-bench-calificacion.yaml" <<'YAML'
apiVersion: batch/v1
kind: Job
metadata:
  name: kube-bench-calificacion
  namespace: default
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app: kube-bench-calificacion
    spec:
      hostPID: true
      nodeSelector:
        node-role.kubernetes.io/control-plane: ""
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      restartPolicy: Never
      containers:
      - name: kube-bench
        image: docker.io/aquasec/kube-bench:v0.16.0@sha256:75506f222d1eb6ce2a751a5533bdc0a3b54c898e2e49e7751d0ee22cfb862679
        command: ["kube-bench","run","--targets=master,controlplane,etcd,policies"]
        volumeMounts:
        - {name: var-lib-etcd, mountPath: /var/lib/etcd, readOnly: true}
        - {name: var-lib-kubelet, mountPath: /var/lib/kubelet, readOnly: true}
        - {name: var-lib-kube-scheduler, mountPath: /var/lib/kube-scheduler, readOnly: true}
        - {name: var-lib-kube-controller-manager, mountPath: /var/lib/kube-controller-manager, readOnly: true}
        - {name: etc-systemd, mountPath: /etc/systemd, readOnly: true}
        - {name: lib-systemd, mountPath: /lib/systemd/, readOnly: true}
        - {name: srv-kubernetes, mountPath: /srv/kubernetes/, readOnly: true}
        - {name: etc-kubernetes, mountPath: /etc/kubernetes, readOnly: true}
        - {name: usr-bin, mountPath: /usr/local/mount-from-host/bin, readOnly: true}
        - {name: etc-cni-netd, mountPath: /etc/cni/net.d/, readOnly: true}
        - {name: opt-cni-bin, mountPath: /opt/cni/bin/, readOnly: true}
      volumes:
      - {name: var-lib-etcd, hostPath: {path: /var/lib/etcd}}
      - {name: var-lib-kubelet, hostPath: {path: /var/lib/kubelet}}
      - {name: var-lib-kube-scheduler, hostPath: {path: /var/lib/kube-scheduler}}
      - {name: var-lib-kube-controller-manager, hostPath: {path: /var/lib/kube-controller-manager}}
      - {name: etc-systemd, hostPath: {path: /etc/systemd}}
      - {name: lib-systemd, hostPath: {path: /lib/systemd}}
      - {name: srv-kubernetes, hostPath: {path: /srv/kubernetes}}
      - {name: etc-kubernetes, hostPath: {path: /etc/kubernetes}}
      - {name: usr-bin, hostPath: {path: /usr/bin}}
      - {name: etc-cni-netd, hostPath: {path: /etc/cni/net.d/}}
      - {name: opt-cni-bin, hostPath: {path: /opt/cni/bin/}}
YAML
$K delete job kube-bench-calificacion --ignore-not-found --wait=true >/dev/null 2>&1
$K apply -f "$T/kube-bench-calificacion.yaml" >/dev/null 2>&1 || exit 1
$K wait --for=condition=complete job/kube-bench-calificacion --timeout=300s >/dev/null 2>&1 || exit 1
$K logs job/kube-bench-calificacion > "$T/informe-calificacion.txt" 2>/dev/null
$K delete job kube-bench-calificacion --ignore-not-found --wait=false >/dev/null 2>&1
grep -qE "^\[PASS\] $CTRL " "$T/informe-calificacion.txt" || exit 1
FALLAS=$(awk '/^== Summary total ==/{f=1} f && /checks FAIL/{print $1; exit}' "$T/informe-calificacion.txt")
test -n "$FALLAS" || exit 1
test "$FALLAS" -lt 10 || exit 1
grep -qxF "FALLAS_DESPUES=$FALLAS" "$D/02-respuesta.txt" || exit 1
echo ok
