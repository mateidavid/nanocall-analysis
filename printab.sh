printab () {
    _delim=$'\t'
    printf "%s" "$1"
    shift
    while [ $# -ge 1 ]; do
        printf "%s%s" "$_delim" "$1"
        shift
    done
    printf "\n"
}

