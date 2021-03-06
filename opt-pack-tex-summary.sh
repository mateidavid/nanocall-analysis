#!/bin/bash
source "$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"/common.sh

join -t$'\t' <(sort ${1}) <(sort ${2}) |
sort -k5n |
cut -f 1,4,5,30,31,42 |
${PYTHON3} ${ROOT_DIR}/highlight-columns |
sed 's/\t/\t\&\t/g;s/_/\\_/g;s/\<0\././g;s/$/\t\\\\/' |
awk -F$'\t' -v OFS=$'\t' '{$1 = "\t&\t\\texttt{" $1 "}"; print}'
