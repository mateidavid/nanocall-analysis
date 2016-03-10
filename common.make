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

TAGS := $(shell [ -r TAGS.local ] && echo TAGS.local) \
	$(shell [ -r ${ROOT_DIR}/TAGS.local ] && echo ${ROOT_DIR}/TAGS.local) \
	${ROOT_DIR}/TAGS
get_tag_list = $(shell cat ${TAGS} | grep -v "^ *\#" | awk '$$1=="${1}" && ($$2=="${2}" || $$2=="*") {print $$3}')
get_tag_value = $(shell cat ${TAGS} | grep -v "^ *\#" | awk '$$1=="${1}" && ($$2=="${2}" || $$2=="*") && $$3=="${3}" {for (i=4;i<=NF;++i) $$(i-3)=$$i; NF-=3; print}' | head -n 1)

get_ds_reference = $(call get_tag_value,reference,${1},reference)
get_ds_subsets = $(call get_tag_list,subset,${1})
get_ds_mappers = $(call get_tag_list,mapper,${1})

get_dss_ds = $(shell echo "${1}" | cut -d. -f1)
get_dss_ss = $(shell echo "${1}" | cut -d. -f2)
get_dss_reference = $(call get_ds_reference,$(call get_dss_ds,${1}))
get_dss_mappers = $(call get_ds_mappers,$(call get_dss_ds,${1}))

remove_duplicates = $(shell echo "${1}" | tr ' ' '\n' | sort | uniq | tr '\n' ' ')
to_upper  = $(shell echo "${1}" | tr '[:lower:]' '[:upper:]')

DATASETS = $(call get_tag_list,dataset,*)
REFERENCES = $(call remove_duplicates,$(foreach ds,${DATASETS},$(call get_ds_reference,${ds})))
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
