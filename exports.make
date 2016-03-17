.SUFFIXES:
MAKEFLAGS += -r
SHELL := /bin/bash

# real path to this Makefile
ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
include ${ROOT_DIR}/common.make

TARGETS = $(foreach ds,${DATASETS},exports/${ds}.pass_10000.summary.main.tex) \
	exports/human_pcr_1.pass_1000.summary.default_transitions.tex \
	exports/human_pcr_1.pass_1000.summary.train_stop.tex \
	exports/human_pcr_1.pass_1000.summary.threads.tex \
	exports/n_vs_m_scale.png

all: ${TARGETS}

list:
	@echo "DATASETS=${DATASETS}"
	@echo "DATASUBSETS=${DATASUBSETS}"
	@echo "REFERENCES=${REFERENCES}"
	@echo "REFERENCES_PER_SUBSET=$(foreach dss,${DATASUBSETS},${dss}:$(call get_dss_reference,${dss}))"
	@echo "MAPPER_PER_SUBSET=$(foreach dss,${DATASUBSETS},${dss}:$(call get_dss_mappers,${dss}))"
	@echo "SPECIAL_TARGETS=${SPECIAL_TARGETS}"
	@echo "TARGETS=${TARGETS}"

clean:
	@rm -f ${TARGETS}

cleanall: clean
	@rm -f ${SPECIAL_TARGETS}

print-%:
	@echo '$*=$($*)'

help: ## This help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

define make_summary_tex
exports/${1}.${2}.summary.${3}.tex: \
	${1}.${2}.summary.${3}.map_pos.tsv \
	${1}.${2}.summary.${3}.errors.tsv \
	${1}.${2}.summary.${3}.runtime.tsv
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	${ROOT_DIR}/tex-summary-main $$^ >$$@ 2>.${1}.${2}.summary.${3}.tex.log
endef
$(foreach dss,${DATASUBSETS},\
$(foreach ds,$(call get_dss_ds,${dss}),\
$(foreach ss,$(call get_dss_ss,${dss}),\
$(foreach opt_pack,$(call get_tag_list,nanocall_opt_pack,${ds}),\
$(eval $(call make_summary_tex,${ds},${ss},${opt_pack}))))))

exports/n_vs_m_scale.png: \
	ecoli_1.pass_10000.metrichor+nanocall~2ss.bwa~ont2d.bam.summary.tsv \
	ecoli_1.pass_10000.metrichor+nanocall~2ss.bwa~ont2d.params_table.tsv \
	ecoli_pcr_1.pass_10000.metrichor+nanocall~2ss.bwa~ont2d.bam.summary.tsv \
	ecoli_pcr_1.pass_10000.metrichor+nanocall~2ss.bwa~ont2d.params_table.tsv \
	human_1.pass_10000.metrichor+nanocall~2ss.bwa~ont2d.bam.summary.tsv \
	human_1.pass_10000.metrichor+nanocall~2ss.bwa~ont2d.params_table.tsv \
	human_pcr_1.pass_10000.metrichor+nanocall~2ss.bwa~ont2d.bam.summary.tsv \
	human_pcr_1.pass_10000.metrichor+nanocall~2ss.bwa~ont2d.params_table.tsv
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	{ \
	  mkdir -p exports && \
	  cd exports && \
	  ${PYTHON3} ${ROOT_DIR}/make-plots \
	    -d Ecoli ${PWD}/ecoli_1.pass_10000.metrichor+nanocall~2ss.bwa~ont2d.{bam.summary,params_table}.tsv \
	    -d "Ecoli PCR" ${PWD}/ecoli_pcr_1.pass_10000.metrichor+nanocall~2ss.bwa~ont2d.{bam.summary,params_table}.tsv \
	    -d Human ${PWD}/human_1.pass_10000.metrichor+nanocall~2ss.bwa~ont2d.{bam.summary,params_table}.tsv \
	    -d "Human PCR" ${PWD}/human_pcr_1.pass_10000.metrichor+nanocall~2ss.bwa~ont2d.{bam.summary,params_table}.tsv; \
	}
