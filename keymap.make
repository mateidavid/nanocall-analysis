.SUFFIXES:
MAKEFLAGS += -r
SHELL := /bin/bash

.PHONY: keymap-list-keys keymap-list-key-prefixes

# set keymap options
ifndef KEYMAP_FILES
KEYMAP_FILES = KEYS
endif
ifndef KEYMAP_PREFIX
KEYMAP_PREFIX = KEYMAP
endif

# load keymap
cat_keymap_file := "cat ${KEYMAP_FILES} | egrep -v \"^ *($$|\#)\""
$(foreach i,$(shell seq 1 $(shell eval ${cat_keymap_file} | wc -l)),\
$(eval $(shell eval ${cat_keymap_file} | awk -v prefix="${KEYMAP_PREFIX}" 'NR==${i} { key=$$1; for(i=2;i<=NF;++i) $$(i-1)=$$i; NF-=1; print prefix "|" key " = " $$0}')))

KEYMAP_KEY_LIST := $(patsubst ${KEYMAP_PREFIX}|%,%,$(filter ${KEYMAP_PREFIX}|%,${.VARIABLES}))

# compute prefix lists
KEYMAP_KEY_PREFIX_LIST_DELIMITED := $(shell eval ${cat_keymap_file} | awk '{n=split($$1,a,"|"); p=""; for(i=1;i<=n;++i) { print p "|"; p = p "|" a[i];} }' | sort | uniq)
KEYMAP_KEY_PREFIX_LIST := $(foreach kp,${KEYMAP_KEY_PREFIX_LIST_DELIMITED},$(patsubst |%,%,$(patsubst %|,%,${kp})))

# initialize prefix lists
$(foreach kp,${KEYMAP_KEY_PREFIX_LIST_DELIMITED},$(eval $(shell { echo "${KEYMAP_PREFIX}${kp} := "; eval ${cat_keymap_file} | awk -v kp="$(patsubst |%,%,${kp})" 'BEGIN{kp_len=length(kp)} substr($$1,1,kp_len)==kp {s=substr($$1,kp_len+1); n=split(s,a,"|"); print a[1];}' | sort | uniq; })))

keymap_val = $(${KEYMAP_PREFIX}|${1})
keymap_key_list = $($(if ${1},${KEYMAP_PREFIX}|${1}|,${KEYMAP_PREFIX}|))

keymap-list-keys:
	@echo "KEYMAP_KEY_LIST=${KEYMAP_KEY_LIST}"
	@$(foreach key,${KEYMAP_KEY_LIST},echo "KEY ${key} = \"$(call keymap_val,${key})\"";)

keymap-list-key-prefixes:
	@echo "KEYMAP_KEY_PREFIX_LIST=${KEYMAP_KEY_PREFIX_LIST}"
	@$(foreach kp,${KEYMAP_KEY_PREFIX_LIST},echo "KEY_PREFIX ${kp} = \"$(call keymap_key_list,${kp})\"";)
