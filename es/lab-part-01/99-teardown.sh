#!/usr/bin/env bash
# lab-part-01 - teardown
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

kind delete cluster --name cks-p01
rm -rf ~/cks-lab/p01
echo "cluster cks-p01 eliminado y workspace borrado; ningun otro cluster fue tocado"
