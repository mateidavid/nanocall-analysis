.SUFFIXES:
MAKEFLAGS += -r
SHELL := /bin/bash

# real path to this Makefile
ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

NANOCALL_DIR = nanocall.dir
LAST_DIR = last.dir
BWA_DIR = bwa.dir

SIMPSONLAB = /.mounts/labs/simpsonlab
THREADS = 8

LASTAL_PARAMS = -r1 -a1 -b1 -q1
LASTAL_TAG = r1a1b1q1

# do not leave failed files around
.DELETE_ON_ERROR:
# do not delete intermediate files
#.SECONDARY:
# fake targets
.PHONY: all list clean cleanall

# format: <dataset> <reference>
DATASETS_FILE = datasets.tab
DATASETS = $(shell awk '{print $$1}' <${DATASETS_FILE})
REFERENCES = $(shell awk '{print $$2}' <${DATASETS_FILE} | uniq)

get_reference = $(shell awk '$$1=="${1}" {print $$2}' <${DATASETS_FILE})
get_subsets = $(shell awk '$$1=="${1}" {print $$3}' <${DATASETS_FILE} | tr ',' ' ')

DATASUBSETS = $(foreach ds,${DATASETS},$(foreach ss,$(call get_subsets,${ds}),${ds}.${ss}))

TARGETS = nanocall.version last.version bwa.version \
	$(foreach ref,${REFERENCES},${ref}.fasta ${ref}.fasta.bwt ${ref}.fasta.lastdb.suf) \
	${DATASETS} \
	$(foreach dss,${DATASUBSETS},${dss}.fofn)

all: ${TARGETS}

list:
	@echo "DATASETS=${DATASETS}"
	@echo "REFERENCES=${REFERENCES}"
	@echo "TARGETS=${TARGETS}"

clean:
	@rm -f ${TARGETS}

cleanall: clean
	@rm -f ${SPECIAL_TARGETS}

print-%:
	@echo '$*=$($*)'

nanocall.version:
	${NANOCALL_DIR}/nanocall --version | awk 'NR==2 {print $$3}'>$@

last.version: ${LAST_DIR}/lastal
	${LAST_DIR}/lastal --version | awk '{print $$2}' >$@

bwa.version: ${BWA_DIR}/bwa
	${BWA_DIR}/bwa |& grep Version | awk '{print $$2}' >$@

ecoli_k12.fasta:
	ln -s ${SIMPSONLAB}/data/references/ecoli_k12.fasta

hs37d5.fasta:
	ln -s ${SIMPSONLAB}/data/references/hs37d5.fa $@

define make_lastdb
${1}.lastdb.suf:
	${LAST_DIR}/lastdb ${1}.lastdb ${1} 2>.$$(@:.suf=.log)
${1}.lastdb.bck: ${1}.lastdb.log
${1}.lastdb.des: ${1}.lastdb.log
${1}.lastdb.prj: ${1}.lastdb.log
${1}.lastdb.sds: ${1}.lastdb.log
${1}.lastdb.ssp: ${1}.lastdb.log
${1}.lastdb.tis: ${1}.lastdb.log
endef
#$(foreach ref,${REFERENCES},$(eval $(call make_lastdb,${ref}.fasta)))

define make_lastdb_index_local
${1}.lastdb.suf:
	for ext in bck des prj sds ssp suf tis; do ln -s ${2}.lastdb.$$$${ext} ${1}.lastdb.$$$${ext}; done
${1}.lastdb.bck: ${1}.lastdb.suf
${1}.lastdb.des: ${1}.lastdb.suf
${1}.lastdb.prj: ${1}.lastdb.suf
${1}.lastdb.sds: ${1}.lastdb.suf
${1}.lastdb.ssp: ${1}.lastdb.suf
${1}.lastdb.tis: ${1}.lastdb.suf
endef
$(eval $(call make_lastdb_index_local,ecoli_k12.fasta,${SIMPSONLAB}/data/references/ecoli_k12.fasta))
$(eval $(call make_lastdb_index_local,hs37d5.fasta,${SIMPSONLAB}/data/references/hs37d5.fa))

define make_bwa_index_local
${1}.bwt:
	for ext in bwt pac ann amb sa; do ln -s ${2}.$$$${ext} ${1}.$$$${ext}; done
${1}.pac: ${1}.bwt
${1}.ann: ${1}.bwt
${1}.amb: ${1}.bwt
${1}.sa: ${1}.bwt
endef
$(eval $(call make_bwa_index_local,ecoli_k12.fasta,${SIMPSONLAB}/data/references/ecoli_k12.fasta))
$(eval $(call make_bwa_index_local,hs37d5.fasta,${SIMPSONLAB}/data/references/hs37d5.fa))

ecoli_pcr_1:
	ln -s ${SIMPSONLAB}/data/nanopore/ecoli/MAP006-PCR_downloads $@

ecoli_pcr_2:
	ln -s ${SIMPSONLAB}/data/nanopore/ecoli/MAP006-PCR-2 $@

human_1:
	ln -s ${SIMPSONLAB}/data/nanopore/oicr_minion/60525_12878 $@

define make_all_fofn
${1}.all.fofn:
	find ${1}/ -name '*.fast5' ! -type d | grep -v "\<raw\>" >$$@
endef
$(foreach ds,${DATASETS},$(eval $(call make_all_fofn,${ds})))

define make_pass_100_fofn
${1}.pass_100.fofn: ${1}.all.fofn
	cat $$< | grep -v "\<fail\>" | head -n 100 >$$@
endef
$(foreach ds,${DATASETS},$(eval $(call make_pass_100_fofn,${ds})))

define make_pass_10_fofn
${1}.pass_10.fofn: ${1}.all.fofn
	cat $$< | grep -v "\<fail\>" | head -n 10 >$$@
endef
$(foreach ds,${DATASETS},$(eval $(call make_pass_10_fofn,${ds})))
