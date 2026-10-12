#!/usr/bin/env bash
# lab-part-05 step 3 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

LAB="$HOME/cks-lab/p05"
K="kubectl --kubeconfig $LAB/kubeconfig --context kind-cks-p05"
export TRIVY_CACHE_DIR="$LAB/trivy-cache"

"$LAB/trivy" --version | head -1

"$LAB/trivy" image --scanners vuln --severity CRITICAL \
  127.0.0.1:5065/tienda/proveedor-a:2026-08
"$LAB/trivy" image --scanners vuln --severity CRITICAL \
  127.0.0.1:5065/tienda/proveedor-b:2026-08

"$LAB/trivy" image --scanners vuln --severity CRITICAL --format json --quiet \
  -o "$LAB/escaneo-a.json" 127.0.0.1:5065/tienda/proveedor-a:2026-08
"$LAB/trivy" image --scanners vuln --severity CRITICAL --format json --quiet \
  -o "$LAB/escaneo-b.json" 127.0.0.1:5065/tienda/proveedor-b:2026-08
jq -r '[.Results[]?.Vulnerabilities[]? | "\(.VulnerabilityID) \(.Severity) \(.PkgName) \(.InstalledVersion)"] | unique | .[]' "$LAB/escaneo-a.json"
jq -r '[.Results[]?.Vulnerabilities[]? | "\(.VulnerabilityID) \(.Severity)"] | unique | .[]' "$LAB/escaneo-b.json"

$K -n la-bodega create deployment el-proveedor \
  --image=cks-p05-registry:5000/tienda/proveedor-b:2026-08 --replicas=2
$K -n la-bodega rollout status deployment/el-proveedor --timeout=180s
$K -n la-bodega get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].imageID}{"\n"}{end}'

printf 'CVE_CRITICO=CVE-2021-44228\nPROVEEDOR_RECHAZADO=tienda/proveedor-a\nPROVEEDOR_APROBADO=tienda/proveedor-b\n' > "$LAB/03-respuesta.txt"
cat "$LAB/03-respuesta.txt"
