.SUFFIXES:
MAKEFLAGS += -r
SHELL := /bin/bash

# real path to this Makefile
ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# do not leave failed files around
.DELETE_ON_ERROR:
# do not delete intermediate files
#.SECONDARY:
# fake targets
.PHONY: all list clean cleanall help

PYTHON3 = venv/bin/python3
NANOCALL = ./nanocall
BWA = ./bwa
SAMTOOLS = ./samtools

TAGS = $(wildcard ${ROOT_DIR}/TAGS*)
get_tag_list = $(shell cat ${TAGS} | grep -v "^ *\#" | awk '$$1=="${1}" && ($$2=="${2}" || $$2=="*") {print $$3}')
get_tag_value = $(shell cat ${TAGS} | grep -v "^ *\#" | awk '$$1=="${1}" && ($$2=="${2}" || $$2=="*") && $$3=="${3}" {for (i=4;i<=NF;++i) $$(i-3)=$$i; NF-=3; print}' | head -n 1)
get_reference = $(call get_tag_value,reference,${1},reference)
get_subsets = $(call get_tag_list,subset,${1})
get_dss_ds = $(shell echo "${1}" | cut -d. -f1)
get_dss_ss = $(shell echo "${1}" | cut -d. -f2)
remove_duplicates = $(shell echo "${1}" | tr ' ' '\n' | sort | uniq | tr '\n' ' ')
to_upper  = $(shell echo "${1}" | tr '[:lower:]' '[:upper:]')

DATASETS = $(call get_tag_list,dataset,*)
REFERENCES = $(call remove_duplicates,$(foreach ds,${DATASETS},$(call get_reference,${ds})))
DATASUBSETS = $(foreach ds,${DATASETS},${ds}.all $(foreach ss,$(call get_subsets,${ds}),${ds}.${ss}))

TARGETS = python3.version nanocall.version bwa.version samtools.version \
	$(foreach ref,${REFERENCES},${ref}--reference ${ref}--bwa-index) \
	$(foreach ds,${DATASETS},${ds}) \
	$(foreach dss,${DATASUBSETS},${dss}.fofn)

all: ${TARGETS}

list:
	@echo "REFERENCES=${REFERENCES}"
	@echo "DATASETS=${DATASETS}"
	@echo "DATASUBSETS=${DATASUBSETS}"
	@echo "TARGETS=${TARGETS}"

clean:
	@rm -f ${TARGETS}

cleanall: clean
	@rm -f ${SPECIAL_TARGETS}

print-%:
	@echo '$*=$($*)'

help: ## This help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

#####################
#
# Python3 VirtualEnv
#
VIRTUALENV = virtualenv
VIRTUALENV_PYTHON3 = python3
VIRTUALENV_OPTS = --system-site-packages
venv/bin/python3: venv/bin/activate
venv/bin/activate: ${ROOT_DIR}/requirements.txt
	test -d venv || ${VIRTUALENV} --python=${VIRTUALENV_PYTHON3} ${VIRTUALENV_OPTS} venv
	venv/bin/pip3 install -Ur $<
	touch venv/bin/activate
python3.version: ${PYTHON3}
	${PYTHON3} --version >$@
#
#####################

#####################
#
# Nanocall
#
NANOCALL_DIR = nanocall.dir
NANOCALL_BUILD_DIR = nanocall.dir/build
NANOCALL_GIT = https://github.com/jts/nanocall.git
NANOCALL_CMAKE_OPTS = -DBUILD_HDF5=1
NANOCALL_MAKE_OPTS =
#
# download
#
${NANOCALL_DIR}/src/CMakeLists.txt:
	git clone --recursive ${NANOCALL_GIT} ${NANOCALL_DIR}
#
# build (default)
#
${NANOCALL_BUILD_DIR}/nanocall/nanocall: ${NANOCALL_DIR}/src/CMakeLists.txt
	mkdir -p ${NANOCALL_BUILD_DIR} && \
	cd ${NANOCALL_BUILD_DIR} && \
	cmake ../src ${NANOCALL_CMAKE_OPTS} && \
	make ${NANOCALL_MAKE_OPTS}
#
# link
#
nanocall: ${NANOCALL_BUILD_DIR}/nanocall/nanocall
	ln -sf $< $@
#
# version
#
nanocall.version: ${NANOCALL}
	${NANOCALL} --version | awk 'NR==2 {print $$3}' >$@
#
#####################

#####################
#
# BWA
#
BWA_DIR = bwa.dir
BWA_GIT = https://github.com/lh3/bwa.git
BWA_MAKE_OPTS = 
#
# download
#
${BWA_DIR}/Makefile:
	git clone ${BWA_GIT} ${BWA_DIR}
#
# build
#
${BWA_DIR}/bwa: ${BWA_DIR}/Makefile
	cd ${BWA_DIR} && \
	make ${BWA_MAKE_OPTS}
#
# link
#
bwa: ${BWA_DIR}/bwa
	ln -sf $< $@
#
# version
#
bwa.version: ${BWA}
	[ -x ${BWA} ] && ${BWA} |& grep Version | awk '{print $$2}' >$@
#
#####################

#####################
#
# Samtools
#
#
# download
#
samtools-1.3/Makefile:
	wget https://github.com/samtools/samtools/releases/download/1.3/samtools-1.3.tar.bz2 -O- | \
	tar -xjf -
#
# build
#
samtools-1.3/samtools: samtools-1.3/Makefile
	cd samtools-1.3 && \
	make
#
# link
#
samtools: samtools-1.3/samtools
	ln -sf $< $@
#
# version
#
samtools.version: ${SAMTOOLS}
	[ -x ${SAMTOOLS} ] && ${SAMTOOLS} --version >$@
#
#####################

#####################
#
# References
#
# Fasta & Fasta index
#
define make_reference
.PHONY: ${1}--reference
${1}--reference: ${1}.fa ${1}.fa.fai
${1}.fa: ${2}
	[ $$< ]
	ln -sf $$< $$@
${1}.fa.fai: ${1}.fa
	if [ -r ${2}.fai ]; then \
	  ln -sf ${2}.fai $$@; \
	else \
	  ${SAMTOOLS} faidx ${1}.fa; \
	fi
endef
$(foreach ref,${REFERENCES},\
  $(eval $(call \
    make_reference,\
    ${ref},\
    $(call get_tag_value,reference_fa,*,${ref}))))
#
# BWA index
#
BWA_INDEX_EXT := bwt pac ann amb sa
define make_bwa_index
.PHONY: ${1}--bwa-index
${1}--bwa-index: ${1}--reference $(foreach ext,${BWA_INDEX_EXT},${1}.fa.${ext}) ${BWA}
${1}.fa.bwt: ${2}
	have_all=1; \
	for ext in ${BWA_INDEX_EXT}; do \
	  [ -r ${2}.$$$${ext} ] || { have_all=; break; }; \
	done; \
	if [ $$$${have_all} ]; then \
	  for ext in ${BWA_INDEX_EXT}; do \
	    ln -sf ${2}.$$$${ext} $$(@:.bwt=).$$$${ext}; \
	  done; \
	else \
	  ${BWA} index ${1}.fa; \
	fi
${1}.fa.pac: ${1}.fa.bwt
${1}.fa.ann: ${1}.fa.bwt
${1}.fa.amb: ${1}.fa.bwt
${1}.fa.sa : ${1}.fa.bwt
endef
$(foreach ref,${REFERENCES},\
  $(eval $(call \
    make_bwa_index,\
    ${ref},\
    $(call get_tag_value,reference_fa,*,${ref}))))
#
# Last index
#
LAST_INDEX_EXT := bck des prj sds ssp suf tis
define make_last_index
.PHONY: ${1}--last-index
${1}--last-index: $(foreach ext,${LAST_INDEX_EXT},${1}.fa.lastdb.${ext}) ${LASTDB}
${1}.fa.lastdb.suf:
	have_all=1; \
	for ext in ${LAST_INDEX_EXT}; do \
	  [ -r ${2}.$$$${ext} ] || { have_all=; break; }; \
	done; \
	if [ $$$${have_all} ]; then \
	  for ext in ${LAST_INDEX_EXT}; do \
	    ln -sf ${2}.$$$${ext} $$(@:.suf=).$$$${ext}; \
	  done; \
	else \
	  ${LASTDB} ${1}.fa.lastdb ${1}.fa; \
	fi
${1}.fa.lastdb.bck: ${1}.fa.lastdb.suf
${1}.fa.lastdb.des: ${1}.fa.lastdb.suf
${1}.fa.lastdb.prj: ${1}.fa.lastdb.suf
${1}.fa.lastdb.sds: ${1}.fa.lastdb.suf
${1}.fa.lastdb.ssp: ${1}.fa.lastdb.suf
${1}.fa.lastdb.tis: ${1}.fa.lastdb.suf
endef
$(eval $(call make_last_index,human,${HUMAN_REFERENCE}.lastdb))
$(eval $(call make_last_index,ecoli,${ECOLI_REFERENCE}.lastdb))
#
#####################

#####################
#
# Datasets
#
#
# paths to fast5 files
#
define make_data_dir
${1}:
	[ -d ${2} ] && [ -r ${2} ] && \
	ln -sf ${2} $$@
endef
$(foreach ds,${DATASETS},\
  $(eval $(call make_data_dir,${ds},$(call get_tag_value,dataset,*,${ds}))))
#
# fofn: all
#
define make_all_fofn
${1}.all.fofn:
	find ${1}/ -name '*.fast5' ! -type d | grep -v "\<raw\>" >$$@
endef
$(foreach ds,${DATASETS},$(eval $(call make_all_fofn,${ds})))
#
# fofn: subsets
#
define make_dss_fofn
${1}.${2}.fofn: ${1}.all.fofn
	cat $$< | eval "$(call get_tag_value,subset,${1},${2})" >$$@
endef
$(foreach dss,$(shell echo "${DATASUBSETS}" | tr ' ' '\n' | grep -v "\.all$$" | tr '\n' ' '),\
  $(eval $(call make_dss_fofn,$(call get_dss_ds,${dss}),$(call get_dss_ss,${dss}))))
#
#####################
