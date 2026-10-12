#!/usr/bin/env bash
# lab-part-02 step 2 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
KC="$HOME/cks-lab/p02/kubeconfig"
D="$HOME/cks-lab/p02"
K="kubectl --kubeconfig $KC"
test -f "$D/02-respuesta.txt" || exit 1
SAFLAG=$($K -n porteria get serviceaccount celador-sin-llaves -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null)
test "$SAFLAG" = "false" || exit 1
PODFLAG=$($K -n porteria get pod ronda-nocturna -o jsonpath='{.spec.automountServiceAccountToken}' 2>/dev/null)
test "$PODFLAG" = "false" || exit 1
CUENTA=$($K -n porteria get pod ronda-nocturna -o jsonpath='{.spec.serviceAccountName}' 2>/dev/null)
test "$CUENTA" = "celador-sin-llaves" || exit 1
LISTO=$($K -n porteria get pod ronda-nocturna -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
test "$LISTO" = "True" || exit 1
PROY=$($K -n porteria get pod ronda-nocturna -o jsonpath='{.spec.volumes[*].projected.sources[*].serviceAccountToken.path}' 2>/dev/null)
test -z "$PROY" || exit 1
SECVOL=$($K -n porteria get pod ronda-nocturna -o jsonpath='{.spec.volumes[*].secret.secretName}' 2>/dev/null)
test -z "$SECVOL" || exit 1
CARPETA=$($K -n porteria exec ronda-nocturna -- sh -c 'ls -d /var/run/secrets/kubernetes.io/serviceaccount >/dev/null 2>&1 && echo EXISTE || echo NO_EXISTE' 2>/dev/null | tr -d '\r\n')
test "$CARPETA" = "NO_EXISTE" || exit 1
RASTRO=$($K -n porteria exec ronda-nocturna -- sh -c 'find / -name token -path "*serviceaccount*" 2>/dev/null | head -1' 2>/dev/null | tr -d '\r\n')
test -z "$RASTRO" || exit 1
ANTES=$($K -n porteria exec ronda-nocturna -- sh -c 'wc -l < /tmp/ronda.log' 2>/dev/null | tr -d ' \r\n')
echo "$ANTES" | grep -qE '^[0-9]+$' || exit 1
test "$ANTES" -ge 2 || exit 1
sleep 8
DESPUES=$($K -n porteria exec ronda-nocturna -- sh -c 'wc -l < /tmp/ronda.log' 2>/dev/null | tr -d ' \r\n')
echo "$DESPUES" | grep -qE '^[0-9]+$' || exit 1
test "$DESPUES" -gt "$ANTES" || exit 1
REINICIOS=$($K -n porteria get pod ronda-nocturna -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
test "$REINICIOS" = "0" || exit 1
grep -qxF "AUTOMOUNT_EN_LA_CUENTA=$SAFLAG" "$D/02-respuesta.txt" || exit 1
grep -qxF "AUTOMOUNT_EN_EL_POD=$PODFLAG" "$D/02-respuesta.txt" || exit 1
grep -qxF "CARPETA_DEL_TOKEN=$CARPETA" "$D/02-respuesta.txt" || exit 1
grep -qxF "CUENTA_DE_LA_RONDA=$CUENTA" "$D/02-respuesta.txt" || exit 1
echo ok
