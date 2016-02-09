.SUFFIXES:
MAKEFLAGS += -r
SHELL := /bin/bash

# real path to this Makefile
ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

NANOCALL_DIR = nanocall.dir
NANOCALL_RELEASE_DIR = nanocall-release.dir
LAST_DIR = last.dir
BWA_DIR = bwa.dir

SIMPSONLAB = /.mounts/labs/simpsonlab
THREADS = 8

NANOCALL_PARAMS = 
NANOCALL_TAG = defaults

LASTAL_PARAMS = -r1 -a1 -b1 -q1
LASTAL_TAG = r1a1b1q1

BWA_PARAMS = -t ${THREADS} -x ont2d
BWA_TAG = ont2d

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

get_reference = $(shell awk '$$1=="$(shell echo "${1}" | cut -d. -f1)" {print $$2}' <${DATASETS_FILE})
get_subsets = $(shell awk '$$1=="${1}" {print $$3}' <${DATASETS_FILE} | tr ',' ' ')

to_upper  = $(shell echo "${1}" | tr '[:lower:]' '[:upper:]')

DATASUBSETS = $(foreach ds,${DATASETS},$(foreach ss,$(call get_subsets,${ds}),${ds}.${ss}))
#ALIGNERS = lastal bwa
ALIGNERS = bwa
ALIGNERS_TAG := $(foreach al,${ALIGNERS},${al}~${$(call to_upper,${al})_TAG})

TARGETS = \
	$(foreach dss,${DATASUBSETS},\
	  $(foreach st,0 1 2,${dss}.metrichor.${st}.fq.gz) \
	  ${dss}.metrichor.params.tsv \
	  ${dss}.nanocall~${NANOCALL_TAG}.fa.gz \
	  $(foreach al,${ALIGNERS_TAG},\
	    $(foreach cs,metrichor nanocall~${NANOCALL_TAG},\
	      ${dss}.${cs}.${al}.bam \
	      ${dss}.${cs}.${al}.bam.summary.tsv) \
	    ${dss}.metrichor+nanocall~${NANOCALL_TAG}.${al}.bam.summary.tsv \
	    ${dss}.metrichor+nanocall~${NANOCALL_TAG}.${al}.error_table.tsv \
	    ${dss}.metrichor+nanocall~${NANOCALL_TAG}.${al}.map_pos_table.tsv \
	    ${dss}.metrichor+nanocall~${NANOCALL_TAG}.${al}.params_table.tsv))

all: ${SPECIAL_TARGETS} ${TARGETS}

list:
	@echo "DATASETS=${DATASETS}"
	@echo "DATASUBSETS=${DATASUBSETS}"
	@echo "REFERENCES=${REFERENCES}"
	@echo "REFERENCES_PER_SUBSET=$(foreach dss,${DATASUBSETS},${dss}:$(call get_reference,${dss}))"
	@echo "ALIGNERS=${ALIGNERS}"
	@echo "ALIGNERS_TAG=${ALIGNERS_TAG}"
	@echo "SPECIAL_TARGETS=${SPECIAL_TARGETS}"
	@echo "TARGETS=${TARGETS}"

clean:
	@rm -f ${TARGETS}

cleanall: clean
	@rm -f ${SPECIAL_TARGETS}

print-%:
	@echo '$*=$($*)'


define extract_metrichor_fq
${1}.metrichor.${2}.fq.gz: ${1}.fofn
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	{ \
	cat $$< \
	| while read -r f; do ${ROOT_DIR}/get_fastq --strand ${2} $$$${f} || true; done \
	| sed 's/_template /_0 /;s/_complement /_1 /;s/_2d /_2 /' \
	| sed 's/^@\([^_]*\)_Basecall_2D_000_\([012]\) \(.*\)$$$$/@\1:\3:metrichor:\2/' \
	| pigz >$$@; \
	} 2>.$$@.log
endef
$(foreach dss,${DATASUBSETS},\
$(foreach st,0 1 2,\
$(eval $(call extract_metrichor_fq,${dss},${st}))))

define get_metrichor_params
${1}.metrichor.params.tsv: ${1}.fofn
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	${ROOT_DIR}/get-model-params --fofn $$< >$$@ 2>.$$@.log
endef
$(foreach dss,${DATASUBSETS},\
$(eval $(call get_metrichor_params,${dss})))

define map_lastal_metrichor_fq
${1}.metrichor.lastal~${LASTAL_TAG}.bam: $(foreach st,0 1 2,${1}.metrichor.${st}.fq.gz) \
	$(call get_reference,${1}).fasta.lastdb.tis
	SGE_RREQ="-N $$@ -l h_tvmem=60G" :; \
	{ \
	zcat $(foreach st,0 1 2,${1}.metrichor.${st}.fq.gz) \
	| last.dir/lastal ${LASTAL_PARAMS} -Q1 $(call get_reference,${1}).fasta.lastdb - \
	| ${ROOT_DIR}/arq5x-nanopore-scripts/maf-convert.py sam - \
	| samtools view -Sh -T $(call get_reference,${1}).fasta - \
	| ${ROOT_DIR}/bam-filter-best-alignment -o $$@; \
	} 2>.$$@.log
endef
$(foreach dss,${DATASUBSETS},\
$(eval $(call map_lastal_metrichor_fq,${dss})))

define map_bwa_metrichor_fq
${1}.metrichor.bwa~${BWA_TAG}.bam: $(foreach st,0 1 2,${1}.metrichor.${st}.fq.gz) \
	$(call get_reference,${1}).fasta.bwt
	SGE_RREQ="-N $$@ -pe smp ${THREADS} -l h_tvmem=60G" :; \
	{ \
	zcat $(foreach st,0 1 2,${1}.metrichor.${st}.fq.gz) \
	| ${BWA_DIR}/bwa mem ${BWA_PARAMS} $(call get_reference,${1}).fasta - \
	| ${ROOT_DIR}/bam-filter-best-alignment -o $$@; \
	} 2>.$$@.log
endef
$(foreach dss,${DATASUBSETS},\
$(eval $(call map_bwa_metrichor_fq,${dss})))

define get_nanocall_fa
${1}.nanocall~${NANOCALL_TAG}.fa.gz: ${1}.fofn
	SGE_RREQ="-N $$@ -pe smp ${THREADS} -l h_tvmem=60G -q !default" :; \
	{\
	  ${NANOCALL_DIR}/nanocall -t ${THREADS} ${NANOCALL_PARAMS} --stats $$(@:.fa.gz=.stats) $$< \
	  | sed 's/:\([01]\)$$$$/:nanocall:\1/' \
	  | pigz >$$@; \
	} 2>$$(@:.fa.gz=.log)
${1}.nanocall~${NANOCALL_TAG}.stats: ${1}.nanocall~${NANOCALL_TAG}.fa.gz
endef
$(foreach dss,${DATASUBSETS},\
$(eval $(call get_nanocall_fa,${dss})))

define map_lastal_nanocall_fa
${1}.nanocall~${NANOCALL_TAG}.lastal~${LASTAL_TAG}.bam: \
	  ${1}.nanocall~${NANOCALL_TAG}.fa.gz $(call get_reference,${1}).fasta.lastdb.tis
	SGE_RREQ="-N $$@ -l h_tvmem=60G" :; \
	{ \
	zc ${1}.nanocall~${NANOCALL_TAG}.fa.gz \
	| last.dir/lastal ${LASTAL_PARAMS} -Q0 $(call get_reference,${1}).fasta.lastdb - \
	| ${ROOT_DIR}/arq5x-nanopore-scripts/maf-convert.py sam - \
	| samtools view -Sh -T $(call get_reference,${1}).fasta - \
	| ${ROOT_DIR}/bam-filter-best-alignment -o $$@; \
	} 2>.$$@.log
endef
$(foreach dss,${DATASUBSETS},\
$(eval $(call map_lastal_nanocall_fa,${dss})))

define map_bwa_nanocall_fa
${1}.nanocall~${NANOCALL_TAG}.bwa~${BWA_TAG}.bam: \
	  ${1}.nanocall~${NANOCALL_TAG}.fa.gz $(call get_reference,${1}).fasta.bwt
	SGE_RREQ="-N $$@ -pe smp ${THREADS} -l h_tvmem=60G" :; \
	{ \
	zc ${1}.nanocall~${NANOCALL_TAG}.fa.gz \
	| ${BWA_DIR}/bwa mem ${BWA_PARAMS} $(call get_reference,${1}).fasta - \
	| ${ROOT_DIR}/bam-filter-best-alignment -o $$@; \
	} 2>.$$@.log
endef
$(foreach dss,${DATASUBSETS},\
$(eval $(call map_bwa_nanocall_fa,${dss})))

define make_bam_summary
${1}.bam.summary.tsv: ${1}.bam
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	${ROOT_DIR}/make-bam-summary $$< >$$@ 2>.$$@.log
endef
$(foreach dss,${DATASUBSETS},\
$(foreach cs,metrichor nanocall~${NANOCALL_TAG},\
$(foreach al,${ALIGNERS_TAG},\
$(eval $(call make_bam_summary,${dss}.${cs}.${al})))))

define make_error_table
${1}.metrichor+nanocall~${NANOCALL_TAG}.${2}.bam.summary.tsv: \
	  ${1}.metrichor.${2}.bam.summary.tsv \
	  ${1}.nanocall~${NANOCALL_TAG}.${2}.bam.summary.tsv
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	{ \
	  diff -q \
	    <(head -n1 ${1}.metrichor.${2}.bam.summary.tsv) \
	    <(head -n1 ${1}.nanocall~${NANOCALL_TAG}.${2}.bam.summary.tsv) >&2 && \
	  { \
	    head -n1 $$<; \
	    for f in $$^; do tail -n+2 $$$$f; done | sort; \
	  }; \
	} >$$@ 2>.$$@.log
${1}.metrichor+nanocall~${NANOCALL_TAG}.${2}.error_table.tsv: \
	  ${1}.metrichor+nanocall~${NANOCALL_TAG}.${2}.bam.summary.tsv
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	${ROOT_DIR}/tabulate-errors $$< >$$@ 2>.$$@.log
endef
$(foreach dss,${DATASUBSETS},\
$(foreach al,${ALIGNERS_TAG},\
$(eval $(call make_error_table,${dss},${al}))))

define make_map_pos_table
${1}.metrichor+nanocall~${NANOCALL_TAG}.${2}.map_pos_table.tsv: \
	  ${1}.metrichor+nanocall~${NANOCALL_TAG}.${2}.bam.summary.tsv
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	${ROOT_DIR}/tabulate-map-pos $$< >$$@ 2>.$$@.log
endef
$(foreach dss,${DATASUBSETS},\
$(foreach al,${ALIGNERS_TAG},\
$(eval $(call make_map_pos_table,${dss},${al}))))

define make_params_table
${1}.metrichor+nanocall~${NANOCALL_TAG}.${2}.params_table.tsv: \
	  ${1}.metrichor+nanocall~${NANOCALL_TAG}.${2}.map_pos_table.tsv \
	  ${1}.metrichor.params.tsv \
	  ${1}.nanocall~${NANOCALL_TAG}.stats
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	{ \
	  join -t$$$$'\t' \
	    <(head -n1 ${1}.metrichor+nanocall~${NANOCALL_TAG}.${2}.map_pos_table.tsv) \
	    <(head -n1 ${1}.metrichor.params.tsv) \
	  | join -t$$$$'\t' \
	    - \
	    <(head -n1 ${1}.nanocall~${NANOCALL_TAG}.stats | cut -f 2,9-); \
	  join -t$$$$'\t' \
	    <(tail -n+2 ${1}.metrichor+nanocall~${NANOCALL_TAG}.${2}.map_pos_table.tsv | sort -k1) \
	    <(tail -n+2 ${1}.metrichor.params.tsv | sort -k1) \
	  | join -t$$$$'\t' \
	    - \
	    <(tail -n+2 ${1}.nanocall~${NANOCALL_TAG}.stats | cut -f 2,9- | sort -k1); \
	} >$$@ 2>.$$@.log
endef
$(foreach dss,${DATASUBSETS},\
$(foreach al,${ALIGNERS_TAG},\
$(eval $(call make_params_table,${dss},${al}))))

define make_error_summary
${1}.summary.errors.tsv: ${1}.metrichor+nanocall~*.error_table.tsv
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	${ROOT_DIR}/error-summary $$^ >$$@ 2>.$$@.log
endef
$(foreach dss,${DATASUBSETS},\
$(eval $(call make_error_summary,${dss})))

define make_map_pos_summary
${1}.summary.map_pos.tsv: ${1}.metrichor+nanocall~*.map_pos_table.tsv
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	${ROOT_DIR}/map-pos-summary $$^ >$$@ 2>.$$@.log
endef
$(foreach dss,${DATASUBSETS},\
$(eval $(call make_map_pos_summary,${dss})))

define make_runtime_measure
${1}.nanocall~${NANOCALL_TAG}.timing.log: ${1}.fofn
	SGE_RREQ="-N $$@ -pe smp ${THREADS} -l h_tvmem=60G -q !default" :; \
	${NANOCALL_RELEASE_DIR}/nanocall -t ${THREADS} ${NANOCALL_PARAMS} $$< 2>$$@ >/dev/null
${1}.nanocall~${NANOCALL_TAG}.timing.stats: ${1}.nanocall~${NANOCALL_TAG}.timing.log
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	${ROOT_DIR}/extract-nanocall-runtimes <$$< >$$@
endef
$(foreach dss,${DATASUBSETS},\
$(eval $(call make_runtime_measure,${dss})))
