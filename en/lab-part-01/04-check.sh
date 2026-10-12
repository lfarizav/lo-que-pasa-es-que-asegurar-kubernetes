#!/usr/bin/env bash
# lab-part-01 step 4 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/cks-lab/p01"
K="kubectl --kubeconfig $D/kubeconfig"
B="$D/binario"
test -f "$D/04-respuesta.txt" || exit 1
MAJOR=$($K get --raw /version 2>/dev/null | sed -n 's/.*"major": *"\([^"]*\)".*/\1/p')
MINOR=$($K get --raw /version 2>/dev/null | sed -n 's/.*"minor": *"\([^"]*\)".*/\1/p')
test -n "$MAJOR" || exit 1
test -n "$MINOR" || exit 1
VERSION=$(curl -sSL --max-time 30 "https://dl.k8s.io/release/stable-$MAJOR.$MINOR.txt" 2>/dev/null | tr -d '[:space:]')
if ! echo "$VERSION" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "ERROR SIN-INTERNET-PARA-CALIFICAR: no se pudo leer stable-$MAJOR.$MINOR.txt de dl.k8s.io."
  echo "El Paso 4 se califica volviendo a pedirle la suma oficial al proyecto, asi que"
  echo "necesita salida a internet en el momento de calificar. Sin esa consulta un"
  echo "aprobado no significaria nada, porque el archivo local lo escribe usted."
  exit 1
fi
grep -qxF "VERSION_DESCARGADA=$VERSION" "$D/04-respuesta.txt" || exit 1
test -f "$B/kubectl" || exit 1
test -x "$B/kubectl" || exit 1
test -f "$B/kubectl.sha256" || exit 1
test -f "$B/kubectl-adulterado" || exit 1
"$B/kubectl" version --client -o json 2>/dev/null | grep -qF "\"gitVersion\": \"$VERSION\"" || exit 1
SHA_REMOTA=$(curl -sSL --max-time 60 "https://dl.k8s.io/release/$VERSION/bin/linux/amd64/kubectl.sha256" 2>/dev/null | tr -d '[:space:]')
if ! echo "$SHA_REMOTA" | grep -qE '^[0-9a-f]{64}$'; then
  echo "ERROR SIN-INTERNET-PARA-CALIFICAR: no se pudo leer la suma oficial de dl.k8s.io."
  exit 1
fi
SHA_ARCHIVO=$(tr -d '[:space:]' < "$B/kubectl.sha256")
test "$SHA_ARCHIVO" = "$SHA_REMOTA" || exit 1
SHA_LOCAL=$(sha256sum "$B/kubectl" | awk '{print $1}')
test "$SHA_LOCAL" = "$SHA_REMOTA" || exit 1
grep -qxF "SHA256_OFICIAL=$SHA_REMOTA" "$D/04-respuesta.txt" || exit 1
SHA_MALA=$(sha256sum "$B/kubectl-adulterado" | awk '{print $1}')
test "$SHA_MALA" != "$SHA_REMOTA" || exit 1
T1=$(stat -c %s "$B/kubectl")
T2=$(stat -c %s "$B/kubectl-adulterado")
test "$T1" = "$T2" || exit 1
grep -qxF "RESULTADO_ORIGINAL=OK" "$D/04-respuesta.txt" || exit 1
grep -qxF "RESULTADO_ADULTERADO=FALLA" "$D/04-respuesta.txt" || exit 1
echo ok
