SHELL := /bin/bash

# real path to this Makefile
ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

NANOCALL_DIR = nanocall.dir
LAST_DIR = last.dir

SIMPSONLAB = /.mounts/labs/simpsonlab
THREADS = 8

LASTAL_PARAMS = -r1 -a1 -b1 -q1
LASTAL_TAG = r1a1b1q1

# do not leave failed files around
.DELETE_ON_ERROR:
# do not delete intermediate files
.SECONDARY:
# fake targets
.PHONY: all list clean cleanall

DATASETS = ecoli_MAP006-PCR-1 ecoli_MAP006-PCR-2
SUBSETS = pass.all pass.100

SPECIAL_TARGETS = nanocall.version last.version ecoli_k12.fasta ecoli_k12.fasta.lastdb.log \
	${DATASETS}

TARGETS = $(foreach d,${DATASETS},$(foreach ss,${SUBSETS},${d}.${ss}.fofn)) \
	$(foreach d,${DATASETS},$(foreach ss,${SUBSETS},$(foreach st,0 1 2,${d}.${ss}.metrichor.${st}.fq.gz ${d}.${ss}.metrichor.${st}.lastal.${LASTAL_TAG}.maf.gz))) \
	$(foreach d,${DATASETS},$(foreach ss,${SUBSETS},${d}.${ss}.nanocall.fa.gz ${d}.${ss}.nanocall.lastal.${LASTAL_TAG}.maf.gz))

all: ${SPECIAL_TARGETS} ${TARGETS}

list:
	@echo "SPECIAL_TARGETS=${SPECIAL_TARGETS}"
	@echo "TARGETS=${TARGETS}"

clean:
	@rm -f ${TARGETS}

cleanall: clean
	@rm -f ${SPECIAL_TARGETS}

print-%:
	@echo '$*=$($*)'

nanocall.version: #${NANOCALL_DIR}/nanocall
	${NANOCALL_DIR}/nanocall --version | awk 'NR==2 {print $$3}'>$@

last.version: ${LAST_DIR}/lastal
	${LAST_DIR}/lastal --version | awk '{print $$2}' >$@

ecoli_k12.fasta:
	ln -s ${SIMPSONLAB}/data/references/ecoli_k12.fasta

ecoli_k12.fasta.lastdb.log:
	${LAST_DIR}/lastdb ecoli_k12.fasta.lastdb ecoli_k12.fasta 2>$@
ecoli_k12.fasta.lastdb.bck: ecoli_k12.fasta.lastdb.log
ecoli_k12.fasta.lastdb.des: ecoli_k12.fasta.lastdb.log
ecoli_k12.fasta.lastdb.prj: ecoli_k12.fasta.lastdb.log
ecoli_k12.fasta.lastdb.sds: ecoli_k12.fasta.lastdb.log
ecoli_k12.fasta.lastdb.ssp: ecoli_k12.fasta.lastdb.log
ecoli_k12.fasta.lastdb.suf: ecoli_k12.fasta.lastdb.log
ecoli_k12.fasta.lastdb.tis: ecoli_k12.fasta.lastdb.log

ecoli_MAP006-PCR-1:
	ln -s ${SIMPSONLAB}/data/nanopore/ecoli/MAP006-PCR_downloads $@

ecoli_MAP006-PCR-2:
	ln -s ${SIMPSONLAB}/data/nanopore/ecoli/MAP006-PCR-2 $@

define get_fofn
${1}.pass.all.fofn:
	find ${1}/pass -name '*.fast5' >$$@
${1}.pass.100.fofn: ${1}.pass.all.fofn
	head -n 100 $$< >$$@
${1}.pass.bad.fofn: ${1}.pass.all.fofn
	pv ${1}.pass.all.fofn | while read -r f; do ${ROOT_DIR}/have_raw_events "$$$$f" || echo "$$$$f"; done >$$@
${1}.pass.good.fofn: ${1}.pass.all.fofn ${1}.pass.bad.fofn
	cat ${1}.pass.all.fofn ${1}.pass.bad.fofn | sort | uniq -u >$$@
endef

$(foreach d,${DATASETS},$(eval $(call get_fofn,${d})))

define extract_metrichor_fq
${1}.${2}.metrichor.${3}.fq.gz: ${1}.${2}.fofn
	cat $$< \
	| while read -r f; do ${ROOT_DIR}/get_fastq --strand ${3} $$$${f}; done \
	| sed 's/_template /_0 /;s/_complement /_1 /;s/_2d /_2 /' \
	| sed 's/^@\([^_]*\)_Basecall_2D_000_\([012]\) \(.*\)$$$$/@\1:\3:metrichor:\2/' \
	| pigz >$$@
endef

$(foreach d,${DATASETS},$(foreach ss,${SUBSETS},$(foreach st,0 1 2,$(eval $(call extract_metrichor_fq,${d},${ss},${st})))))


define nanocall_fa
${1}.${2}.nanocall.fa.gz: ${1}.${2}.fofn
	SGE_RREQ="-N $$@ -pe smp ${THREADS} -l h_tvmem=60G" :; \
	{\
	nanocall.dir/nanocall -t ${THREADS} $$< --stats $$(@:.fa.gz=.stats) \
	  2> >(tee $$(@:.fa.gz=.log) >&2) \
	| sed 's/:\([01]\)$$$$/:nanocall:\1/' | pigz >$$@; \
	}
endef

$(foreach d,${DATASETS},$(foreach ss,${SUBSETS},$(eval $(call nanocall_fa,${d},${ss}))))

define map_fq_gz
${1}.lastal.${LASTAL_TAG}.maf.gz: ${1}.fq.gz ecoli_k12.fasta.lastdb.tis
	SGE_RREQ="-N $$@ -l h_tvmem=20G" :; \
	{ \
	zc $$< \
	| last.dir/lastal ${LASTAL_PARAMS} -Q1 ecoli_k12.fasta.lastdb - \
	| pigz >$$@; \
	} 2>$$@.log
endef

$(foreach d,${DATASETS},$(foreach ss,${SUBSETS},$(foreach st,0 1 2,$(eval $(call map_fq_gz,${d}.${ss}.metrichor.${st})))))


define map_fa_gz
${1}.lastal.${LASTAL_TAG}.maf.gz: ${1}.fa.gz ecoli_k12.fasta.lastdb.tis
	SGE_RREQ="-N $$@ -l h_tvmem=20G" :; \
	{ \
	zc $$< \
	| last.dir/lastal ${LASTAL_PARAMS} -Q0 ecoli_k12.fasta.lastdb - \
	| pigz >$$@; \
	} 2>$$@.log
endef

$(foreach d,${DATASETS},$(foreach ss,${SUBSETS},$(eval $(call map_fa_gz,${d}.${ss}.nanocall))))
