ifndef ROOT_DIR
$(error Do not use this makefile directly)
endif

define extract_metrichor_fq
${1}.metrichor.${2}.fq.gz: ${1}.fofn | python3.version
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	{ \
	  ${PYTHON3} ${ROOT_DIR}/get-fastq --strand ${2} --fofn $$< | \
	  sed 's/_template /_0 /;s/_complement /_1 /;s/_2d /_2 /' | \
	  sed 's/^@\([^_]*\)_[^ ]*_\([012]\) \(.*\)$$$$/@\1:\3:metrichor:\2/' | \
	  ${GZIP} >$$@; \
	} 2>.$$@.log
endef
$(foreach dss,${DATASUBSETS},\
$(foreach st,0 1 2,\
$(eval $(call extract_metrichor_fq,${dss},${st}))))

define get_metrichor_params
${1}.metrichor.params.tsv: ${1}.fofn
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	${PYTHON3} ${ROOT_DIR}/get-metrichor-params --fofn $$< >$$@ 2>.$$@.log
endef
$(foreach dss,${DATASUBSETS},\
$(eval $(call get_metrichor_params,${dss})))

define run_bwa_unpaired
# parameters:
# 1 = destination bam file
# 2 = input files
# 3 = reference
# 4 = bwa options
# 5 = number of threads
# 6 = RAM request
${1}: ${2} | bwa.version ${3}--bwa-index
	SGE_RREQ="-N $$@ -pe smp ${5} -l h_tvmem=${6}" :; \
	{ \
	  zcat -f ${2} | \
	  ${BWA} mem -t ${5} ${4} ${3}.fa - | \
	  ${SAMTOOLS} view -F 0x900 -b -; \
	} >$$@ 2>.$$@.log
${1}_summary.tsv: ${1}
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	{ \
	  ${PYTHON3} ${ROOT_DIR}/make-bam-summary $$< 2>.$$@.log | \
	  { read -e line; echo "$$$$line"; sort; }; \
	} >$$@
endef

# parameters:
# 1 = ds
# 2 = ss
# 3 = ref
# 4 = bwa_opts_tag
run_bwa_metrichor_fq = $(call run_bwa_unpaired,${1}.${2}.metrichor.bwa~${4}.bam,$(foreach st,0 1 2,${1}.${2}.metrichor.${st}.fq.gz),${3},$(call get_mapper_opt_cmd,bwa,${4}),${THREADS},14G)

$(foreach dss,${DATASUBSETS},\
$(foreach ds,$(call get_dss_ds,${dss}),\
$(foreach ss,$(call get_dss_ss,${dss}),\
$(foreach ref,$(call get_ds_reference,${ds}),\
$(foreach bwa_opts,$(call get_ds_mapper_opt_list,${ds},bwa),\
$(eval $(call run_bwa_metrichor_fq,${ds},${ss},${ref},${bwa_opts})))))))

# parameters:
# 1 = ds
# 2 = ss
# 3 = nanocall_opts_tag
# 4 = ref
# 5 = bwa_opts_tag
run_bwa_nanocall_fa = $(call run_bwa_unpaired,${1}.${2}.nanocall~${3}.bwa~${5}.bam,${1}.${2}.nanocall~${3}.fa.gz,${4},$(call get_mapper_opt_cmd,bwa,${5}),${THREADS},14G)

$(foreach dss,${DATASUBSETS},\
$(foreach ds,$(call get_dss_ds,${dss}),\
$(foreach ss,$(call get_dss_ss,${dss}),\
$(foreach ref,$(call get_ds_reference,${ds}),\
$(foreach nanocall_opts,$(call get_ds_nanocall_opt_list,${ds}),\
$(foreach bwa_opts,$(call get_ds_mapper_opt_list,${ds},bwa),\
$(eval $(call run_bwa_nanocall_fa,${ds},${ss},${nanocall_opts},${ref},${bwa_opts}))))))))

define run_nanocall
# parameters:
# 1 = prefix of destination fa.gz file
# 2 = input fofn
# 3 = nanocall params
# 4 = num threads
${1}.fa.gz: ${2} | python3.version nanocall.version
	SGE_RREQ="-N $$@ -pe smp ${4} ${NANOCALL_SGE_OPTS}" :; \
	{ \
	  if [ "${CACHE_FILES}" = "1" ]; then \
	    dir=$$$$(mktemp -d); \
	    cd $$$$dir; \
	    rsync -a ${PWD}/${2} ./; \
	    rsync -a --files-from=${2} ${PWD}/ ./; \
	  fi; \
	  ${NANOCALL} -t ${4} ${3} --stats ${1}.stats ${2} 2>${PWD}/${1}.log | \
	  sed 's/:\([01]\)$$$$/:nanocall:\1/' | \
	  ${GZIP} >$$@; \
	  if [ "${CACHE_FILES}" = "1" ]; then \
	    rsync -a $$@ ${1}.stats ${PWD}/; \
	    cd ${PWD}; \
	    rm -rf $$$$dir; \
	  fi; \
	} 2>.$$@.log
${1}.stats: ${1}.fa.gz
${1}.log: ${1}.fa.gz
endef

$(foreach dss,${DATASUBSETS},\
$(foreach ds,$(call get_dss_ds,${dss}),\
$(foreach ss,$(call get_dss_ss,${dss}),\
$(foreach nanocall_opts,$(call get_ds_nanocall_opt_list,${ds}),\
$(eval $(call run_nanocall,${dss}.nanocall~${nanocall_opts},${dss}.fofn,$(call get_nanocall_opt_cmd,${nanocall_opts}),$(call get_nanocall_opt_threads,${nanocall_opts})))))))

define make_m_vs_n_tables
${1}.metrichor+nanocall~${2}.${3}.bam_summary.tsv: \
	  ${1}.metrichor.${3}.bam_summary.tsv \
	  ${1}.nanocall~${2}.${3}.bam_summary.tsv
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	{ \
	  diff -q \
	    <(head -n1 ${1}.metrichor.${3}.bam_summary.tsv) \
	    <(head -n1 ${1}.nanocall~${2}.${3}.bam_summary.tsv) >&2; \
	  head -n1 $$<; \
	  sort -m \
	    <(tail -n+2 ${1}.metrichor.${3}.bam_summary.tsv) \
	    <(tail -n+2 ${1}.nanocall~${2}.${3}.bam_summary.tsv); \
	} >$$@ 2>.$$@.log
${1}.metrichor+nanocall~${2}.${3}.bam_table.tsv: \
	  ${1}.metrichor+nanocall~${2}.${3}.bam_summary.tsv
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	${PYTHON3} ${ROOT_DIR}/tabulate-mappings $$< >$$@ 2>.$$@.log
${1}.metrichor+nanocall~${2}.${3}.full_table.tsv: \
	  ${1}.metrichor+nanocall~${2}.${3}.bam_table.tsv \
	  ${1}.metrichor.params.tsv \
	  ${1}.nanocall~${2}.stats
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	{ \
	  join -t$$$$'\t' \
	    <(head -n1 ${1}.metrichor+nanocall~${2}.${3}.bam_table.tsv) \
	    <(head -n1 ${1}.metrichor.params.tsv) | \
	  join -t$$$$'\t' \
	    - \
	    <(head -n1 ${1}.nanocall~${2}.stats | cut -f 2-); \
	  join -t$$$$'\t' \
	    <(tail -n+2 ${1}.metrichor+nanocall~${2}.${3}.bam_table.tsv | sort -k1) \
	    <(tail -n+2 ${1}.metrichor.params.tsv | sort -k1) | \
	  join -t$$$$'\t' \
	    - \
	    <(tail -n+2 ${1}.nanocall~${2}.stats | cut -f 2- | sort -k1); \
	} >$$@ 2>.$$@.log
endef

$(foreach dss,${DATASUBSETS},\
$(foreach ds,$(call get_dss_ds,${dss}),\
$(foreach ss,$(call get_dss_ss,${dss}),\
$(foreach nanocall_opts,$(call get_ds_nanocall_opt_list,${ds}),\
$(foreach mapper,$(call get_ds_mappers,${ds}),\
$(foreach mapper_opts,$(call get_ds_mapper_opt_list,${ds},${mapper}),\
$(eval $(call make_m_vs_n_tables,${dss},${nanocall_opts},${mapper}~${mapper_opts}))))))))

define make_meta_targets_ds_ss
.PHONY: ${1}.${2}.metrichor
${1}.${2}.metrichor: \
	${1}.${2}.metrichor.params.tsv \
	$(foreach mapper,$(call get_ds_mappers,${1}),\
	$(foreach mapper_opts,$(call get_ds_mapper_opt_list,${1},${mapper}),\
	${1}.${2}.metrichor.${mapper}~${mapper_opts}.bam_summary.tsv))
endef
$(foreach dss,${DATASUBSETS},\
$(foreach ds,$(call get_dss_ds,${dss}),\
$(foreach ss,$(call get_dss_ss,${dss}),\
$(eval $(call make_meta_targets_ds_ss,${ds},${ss})))))

define make_meta_targets_ds_ss_no
.PHONY: ${1}.${2}.nanocall~${3} \
	${1}.${2}.metrichor+nanocall~${3}
${1}.${2}.nanocall~${3}: \
	${1}.${2}.nanocall~${3}.fa.gz \
	${1}.${2}.nanocall~${3}.stats \
	$(foreach mapper,$(call get_ds_mappers,${1}),\
	$(foreach mapper_opts,$(call get_ds_mapper_opt_list,${1},${mapper}),\
	${1}.${2}.nanocall~${3}.${mapper}~${mapper_opts}.bam_summary.tsv))
${1}.${2}.metrichor+nanocall~${3}: \
	$(foreach mapper,$(call get_ds_mappers,${1}),\
	$(foreach mapper_opts,$(call get_ds_mapper_opt_list,${1},${mapper}),\
	${1}.${2}.metrichor+nanocall~${3}.${mapper}~${mapper_opts}.full_table.tsv))
endef
$(foreach dss,${DATASUBSETS},\
$(foreach ds,$(call get_dss_ds,${dss}),\
$(foreach ss,$(call get_dss_ss,${dss}),\
$(foreach nanocall_opts,$(call get_ds_nanocall_opt_list,${ds}),\
$(eval $(call make_meta_targets_ds_ss_no,${ds},${ss},${nanocall_opts}))))))

#
# option packs
#
define make_meta_targets_opt_pack
.PHONY: ${1}.${2}.nanocall--${3} \
	${1}.${2}.metrichor+nanocall--${3}
${1}.${2}.nanocall--${3}: \
	$(foreach nanocall_opts,$(call get_pack_nanocall_opt_list,${3}),\
	${1}.${2}.nanocall~${nanocall_opts})
${1}.${2}.metrichor+nanocall--${3}: \
	$(foreach nanocall_opts,$(call get_pack_nanocall_opt_list,${3}),\
	${1}.${2}.metrichor+nanocall~${nanocall_opts}) \
	${1}.${2}.summary.${3}.mapping.tsv \
	${1}.${2}.summary.${3}.runtime.tsv
${1}.${2}.summary.${3}.mapping.tsv: \
	$(foreach nanocall_opts,$(call get_pack_nanocall_opt_list,${3}),\
	${1}.${2}.metrichor+nanocall~${nanocall_opts}.bwa~ont2d.full_table.tsv)
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	paste \
	  <( \
	    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "dataset" "subset" "opt_pack" "nanocall_tag" "aln" "aln_tag"; \
	    for n_opt in $(call get_pack_nanocall_opt_list,${3}); do \
	      printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$1" "$2" "$3" "$$$$n_opt" "bwa" "ont2d"; \
	    done; \
	  ) \
	  <(${ROOT_DIR}/mapping-summary $$^) \
	  >$$@ 2>.$$@.log
${1}.${2}.summary.${3}.runtime.tsv: ${1}.${2}.metrichor.2.fq.gz \
	$(foreach nanocall_opts,$(call get_pack_nanocall_opt_list,${3}),\
	${1}.${2}.nanocall~${nanocall_opts}.log)
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	INPUT_SIZE=$$$$(zcat -f ${1}.${2}.metrichor.2.fq.gz | paste - - | paste - - | cut -f 2 | wc -c) \
	${ROOT_DIR}/runtime-summary \
	$(foreach nanocall_opts,$(call get_pack_nanocall_opt_list,${3}),\
	${1}.${2}.nanocall~${nanocall_opts}.log) \
	>$$@ 2>.$$@.log
endef
$(foreach dss,${DATASUBSETS},\
$(foreach ds,$(call get_dss_ds,${dss}),\
$(foreach ss,$(call get_dss_ss,${dss}),\
$(foreach opt_pack,$(call get_ds_nanocall_opt_pack_list,${ds}),\
$(eval $(call make_meta_targets_opt_pack,${ds},${ss},${opt_pack}))))))
