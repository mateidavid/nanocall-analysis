# real path to this Makefile
ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# do not leave failed files around
.DELETE_ON_ERROR:
# do not delete intermediate files
#.SECONDARY:
# fake targets
.PHONY: all list clean cleanall help

TOOLS_DIR := ${PWD}/tools
SRC_DIR := ${PWD}/src
CACHE_DIR := ${PWD}/cache
DATA_DIR := ${PWD}/data

HDF5_ROOT = ${TOOLS_DIR}
PYTHON3 = ${TOOLS_DIR}/bin/python3
NANOCALL = ${TOOLS_DIR}/bin/nanocall
BWA = ${TOOLS_DIR}/bin/bwa
SAMTOOLS = ${TOOLS_DIR}/bin/samtools

GZIP := $(shell if which pigz >/dev/null 2>&1; then echo pigz; else echo gzip; fi)

HUMAN_REFERENCE = ${DATA_DIR}/human.fa
ECOLI_REFERENCE = ${DATA_DIR}/ecoli.fa

KEYMAP_FILES := \
	${ROOT_DIR}/KEYS \
	$(shell [ -r ${ROOT_DIR}/KEYS.local ] && echo ${ROOT_DIR}/KEYS.local) \
	$(shell [ -r KEYS.local ] && echo KEYS.local)

include ${ROOT_DIR}/keymap.make

get_ds_reference = $(call keymap_val,dataset|${1}|reference)
get_ds_subsets = $(or $(call keymap_val,dataset|${1}|subsets),$(call keymap_key_list,subset))
get_ds_mappers = $(or \
	$(call keymap_key_list,dataset|${1}|mapper_option_list),\
	$(call keymap_key_list,mapper_option))
get_ds_mapper_opt_list = $(or \
	$(call keymap_val,dataset|${1}|mapper_option_list|${2}),\
	$(call keymap_key_list,mapper_option|${2}))
get_ds_nanocall_opt_list = $(or \
	$(call keymap_val,dataset|${1}|nanocall_option_list), \
	$(call keymap_key_list,nanocall_option))
get_ds_nanocall_opt_pack_list = $(or \
	$(call keymap_val,dataset|${1}|nanocall_option_pack_list), \
	$(call keymap_key_list,nanocall_option_pack))

get_dss_ds = $(word 1,$(subst ., ,${1}))
get_dss_ss = $(word 2,$(subst ., ,${1}))
get_dss_reference = $(call get_ds_reference,$(call get_dss_ds,${1}))
get_dss_mappers = $(call get_ds_mappers,$(call get_dss_ds,${1}))

get_mapper_opt_cmd = $(call keymap_val,mapper_option|${1}|${2})
get_nanocall_opt_cmd = $(call keymap_val,nanocall_option|${1}|cmd)
get_nanocall_opt_threads = $(or $(call keymap_val,nanocall_option|${1}|threads),${THREADS})
get_pack_nanocall_opt_list = $(call keymap_val,nanocall_option_pack|${1})

remove_duplicates = $(shell echo "${1}" | tr ' ' '\n' | sort | uniq | tr '\n' ' ')
to_upper  = $(shell echo "${1}" | tr '[:lower:]' '[:upper:]')

DATASETS = $(call keymap_key_list,dataset)
REFERENCES = $(call keymap_key_list,reference)
DATASUBSETS = $(foreach ds,${DATASETS},${ds}.all $(foreach ss,$(call get_ds_subsets,${ds}),${ds}.${ss}))

# add rules to download and unpack source tarball
# 1 = URL / file
# 2 = MD5SUM
# 3 = Destination dir name
define get_url
${CACHE_DIR}/$(shell basename "${1}"):
	mkdir -p ${CACHE_DIR} && \
	if [ -r "${1}" ]; then \
	  ln -s "${1}" $$@; \
	else \
	  wget -L "${1}" -O $$@ && \
	  test "$$$$(md5sum <"$$@") | awk '{print $$$$1}')" = "${2}"; \
	fi
${3}: ${CACHE_DIR}/$(shell basename "${1}")
	mkdir -p $$$$(dirname ${3}) && \
	tar -xf $$< -C $$$$(dirname ${3}) && \
	test -d $$@
endef
