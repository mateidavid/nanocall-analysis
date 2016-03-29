_prog_path=$(readlink -e "${BASH_SOURCE[1]}")
_prog_name=$(basename "$_prog_path")
_prog_dir=$(dirname "$_prog_path")
ROOT_DIR=${ROOT_DIR:-${_prog_dir}}

printab () {
    IFS=$'\t' eval 'echo "$*"'
}

trap 'echo "exit code $?: LINENO=$LINENO BASH_LINENO=\"${BASH_LINENO[@]}\" FUNCNAME=\"${FUNCNAME[@]}\"" >&2' ERR
set -eEu
