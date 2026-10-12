#!/usr/bin/env bash
# lab-part-06 step 4 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
W="$HOME/cks-lab/p06"; K="kubectl --kubeconfig $W/kubeconfig"; R="$W/04-respuesta.txt"
M="$W/bin/minuta"
test -f "$R" || exit 1
grep -qxF "RECURSO=pods" "$R" || exit 1
grep -qxF "SUBRECURSO=exec" "$R" || exit 1
grep -qxF "NIVEL=Metadata" "$R" || exit 1
grep -qxF "ETAPAS=ResponseStarted,ResponseComplete" "$R" || exit 1
VERBO=$(grep -m1 '^VERBO=' "$R" | cut -d= -f2-)
test -n "$VERBO" || exit 1
"$M" 2>/dev/null | jq -e --arg v "$VERBO" 'select(.objectRef.namespace=="el-local"
  and .objectRef.resource=="pods" and .objectRef.subresource=="exec" and .verb==$v
  and .level=="Metadata" and .stage=="ResponseComplete"
  and (.objectRef.name|startswith("caja-registradora-")))' >/dev/null 2>&1 || exit 1
"$M" 2>/dev/null | jq -e 'select(.objectRef.namespace=="el-local"
  and .objectRef.subresource=="exec" and .stage=="ResponseStarted")' >/dev/null 2>&1 || exit 1
test "$($K -n el-local get deploy caja-registradora -o jsonpath='{.spec.replicas}' 2>/dev/null)" = "1" || exit 1
$K -n el-local rollout status deployment/caja-registradora --timeout=240s >/dev/null 2>&1 || exit 1
test "$($K -n el-local get deploy caja-registradora -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "1" || exit 1
test "$($K -n el-local get deploy caja-registradora \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="caja")].securityContext.readOnlyRootFilesystem}' 2>/dev/null)" = "true" || exit 1
PRIV=$($K -n el-local get deploy caja-registradora \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="caja")].securityContext.privileged}' 2>/dev/null)
test "$PRIV" != "true" || exit 1
HP=$($K -n el-local get deploy caja-registradora \
  -o jsonpath='{range .spec.template.spec.volumes[*]}{.hostPath.path}{"\n"}{end}' 2>/dev/null | grep -c . || true)
test "${HP:-0}" -eq 0 || exit 1
test "$($K -n el-local get svc caja-registradora -o jsonpath='{.spec.selector.app}' 2>/dev/null)" = "caja-registradora" || exit 1
POD=""
for p in $($K -n el-local get pod -l app=caja-registradora \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
  LISTO=$($K -n el-local get pod "$p" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  MUERE=$($K -n el-local get pod "$p" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null)
  if [ "$LISTO" = "True" ] && [ -z "$MUERE" ]; then POD="$p"; break; fi
done
test -n "$POD" || exit 1
S="sonda-$(date +%s)"
$K -n el-local exec "$POD" -c caja -- sh -c "touch /$S" >/dev/null 2>&1 && exit 1
$K -n el-local exec "$POD" -c caja -- sh -c "touch /tmp/$S" >/dev/null 2>&1 && exit 1
$K -n el-local exec "$POD" -c caja -- sh -c "touch /www/$S && rm -f /www/$S" >/dev/null 2>&1 || exit 1
$K -n el-local exec "$POD" -c caja -- sh -c 'test -s /var/log/local/ventas.log' >/dev/null 2>&1 || exit 1
$K -n el-local exec "$POD" -c caja -- sh -c 'test -s /www/index.html' >/dev/null 2>&1 || exit 1
$K -n el-local get pod mandadero >/dev/null 2>&1 || exit 1
COD=""
for i in 1 2 3 4 5 6; do
  COD=$($K -n el-local exec mandadero -- curl -s -o /dev/null -w '%{http_code}' --max-time 8 \
    http://caja-registradora.el-local.svc.cluster.local/ 2>/dev/null)
  [ "$COD" = "200" ] && break
  sleep 5
done
test "$COD" = "200" || exit 1
echo ok
