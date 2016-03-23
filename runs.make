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
	${PYTHON3} ${ROOT_DIR}/get-model-params --fofn $$< >$$@ 2>.$$@.log
endef
$(foreach dss,${DATASUBSETS},\
$(eval $(call get_metrichor_params,${dss})))

define run_bwa_unpaired
# parameters:
# 1 = destination bam file
# 2 = input files
# 3 = index prefix
# 4 = bwa options
# 5 = number of threads
# 6 = RAM request
${1}: ${2} ${3}.bwt | bwa.version ${3}--bwa-index
	SGE_RREQ="-N $$@ -pe smp ${5} -l h_tvmem=${6}" :; \
	{ \
	  zcat -f ${2} | \
	  ${BWA} mem -t ${5} ${4} ${3} - | \
	  ${PYTHON3} ${ROOT_DIR}/bam-filter-best-alignment; \
	} >$$@ 2>.$$@.log
${1}.summary.tsv: ${1}
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	${PYTHON3} ${ROOT_DIR}/make-bam-summary $$< >$$@ 2>.$$@.log
endef

# parameters:
# 1 = ds
# 2 = ss
# 3 = ref_fa
# 4 = bwa_opts_tag
run_bwa_metrichor_fq = $(call run_bwa_unpaired,${1}.${2}.metrichor.bwa~${4}.bam,$(foreach st,0 1 2,${1}.${2}.metrichor.${st}.fq.gz),${3},$(call get_mapper_opt_cmd,bwa,${4}),${THREADS},14G)

$(foreach dss,${DATASUBSETS},\
$(foreach ds,$(call get_dss_ds,${dss}),\
$(foreach ss,$(call get_dss_ss,${dss}),\
$(foreach ref,$(call get_ds_reference,${ds}),\
$(foreach bwa_opts,$(call get_ds_mapper_opt_list,${ds},bwa),\
$(eval $(call run_bwa_metrichor_fq,${ds},${ss},${ref}.fa,${bwa_opts})))))))

# parameters:
# 1 = ds
# 2 = ss
# 3 = nanocall_opts_tag
# 4 = ref_fa
# 5 = bwa_opts_tag
run_bwa_nanocall_fa = $(call run_bwa_unpaired,${1}.${2}.nanocall~${3}.bwa~${5}.bam,${1}.${2}.nanocall~${3}.fa.gz,${4},$(call get_mapper_opt_cmd,bwa,${5}),${THREADS},14G)

$(foreach dss,${DATASUBSETS},\
$(foreach ds,$(call get_dss_ds,${dss}),\
$(foreach ss,$(call get_dss_ss,${dss}),\
$(foreach ref,$(call get_ds_reference,${ds}),\
$(foreach nanocall_opts,$(call get_ds_nanocall_opt_list,${ds}),\
$(foreach bwa_opts,$(call get_ds_mapper_opt_list,${ds},bwa),\
$(eval $(call run_bwa_nanocall_fa,${ds},${ss},${nanocall_opts},${ref}.fa,${bwa_opts}))))))))

define run_nanocall
# parameters:
# 1 = prefix of destination fa.gz file
# 2 = input fofn
# 3 = nanocall params
# 4 = num threads
# 5 = RAM request
${1}.fa.gz: ${2} | python3.version nanocall.version
	SGE_RREQ="-N $$@ -pe smp ${4} -l h_tvmem=${5} -l h_rt=48:0:0 -l s_rt=48:0:0 -q !default" :; \
	{ \
	  dir=$$$$(mktemp -d); \
	  cd $$$$dir; \
	  rsync -a ${PWD}/${2} ./; \
	  rsync -a --files-from=${2} ${PWD}/ ./; \
	  ${NANOCALL} -t ${4} ${3} --stats ${1}.stats ${2} 2>${PWD}/${1}.log | \
	  sed 's/:\([01]\)$$$$/:nanocall:\1/' | \
	  ${GZIP} >$$@; \
	  rsync -a $$@ ${1}.stats ${PWD}/; \
	  cd ${PWD}; \
	  rm -rf $$$$dir; \
	} 2>.$$@.log
${1}.stats: ${1}.fa.gz
${1}.log: ${1}.fa.gz
endef

$(foreach dss,${DATASUBSETS},\
$(foreach ds,$(call get_dss_ds,${dss}),\
$(foreach ss,$(call get_dss_ss,${dss}),\
$(foreach nanocall_opts,$(call get_ds_nanocall_opt_list,${ds}),\
$(eval $(call run_nanocall,${dss}.nanocall~${nanocall_opts},${dss}.fofn,$(call get_nanocall_opt_cmd,${nanocall_opts}),$(call get_nanocall_opt_threads,${nanocall_opts}),15G))))))

define make_m_vs_n_tables
${1}.metrichor+nanocall~${2}.${3}.bam.summary.tsv: \
	  ${1}.metrichor.${3}.bam.summary.tsv \
	  ${1}.nanocall~${2}.${3}.bam.summary.tsv
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	{ \
	  diff -q \
	    <(head -n1 ${1}.metrichor.${3}.bam.summary.tsv) \
	    <(head -n1 ${1}.nanocall~${2}.${3}.bam.summary.tsv) >&2 && \
	  { \
	    head -n1 $$<; \
	    for f in $$^; do tail -n+2 $$$$f; done | sort; \
	  }; \
	} >$$@ 2>.$$@.log
${1}.metrichor+nanocall~${2}.${3}.error_table.tsv: \
	  ${1}.metrichor+nanocall~${2}.${3}.bam.summary.tsv
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	${PYTHON3} ${ROOT_DIR}/tabulate-errors $$< >$$@ 2>.$$@.log
${1}.metrichor+nanocall~${2}.${3}.map_pos_table.tsv: \
	  ${1}.metrichor+nanocall~${2}.${3}.bam.summary.tsv
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	${PYTHON3} ${ROOT_DIR}/tabulate-map-pos $$< >$$@ 2>.$$@.log
${1}.metrichor+nanocall~${2}.${3}.params_table.tsv: \
	  ${1}.metrichor+nanocall~${2}.${3}.map_pos_table.tsv \
	  ${1}.metrichor.params.tsv \
	  ${1}.nanocall~${2}.stats
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	{ \
	  join -t$$$$'\t' \
	    <(head -n1 ${1}.metrichor+nanocall~${2}.${3}.map_pos_table.tsv) \
	    <(head -n1 ${1}.metrichor.params.tsv) | \
	  join -t$$$$'\t' \
	    - \
	    <(head -n1 ${1}.nanocall~${2}.stats | cut -f 2,9-); \
	  join -t$$$$'\t' \
	    <(tail -n+2 ${1}.metrichor+nanocall~${2}.${3}.map_pos_table.tsv | sort -k1) \
	    <(tail -n+2 ${1}.metrichor.params.tsv | sort -k1) | \
	  join -t$$$$'\t' \
	    - \
	    <(tail -n+2 ${1}.nanocall~${2}.stats | cut -f 2,9- | sort -k1); \
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
	${1}.${2}.metrichor.${mapper}~${mapper_opts}.bam.summary.tsv))
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
	${1}.${2}.nanocall~${3}.${mapper}~${mapper_opts}.bam.summary.tsv))
${1}.${2}.metrichor+nanocall~${3}: \
	$(foreach mapper,$(call get_ds_mappers,${1}),\
	$(foreach mapper_opts,$(call get_ds_mapper_opt_list,${1},${mapper}),\
	${1}.${2}.metrichor+nanocall~${3}.${mapper}~${mapper_opts}.bam.summary.tsv \
	${1}.${2}.metrichor+nanocall~${3}.${mapper}~${mapper_opts}.error_table.tsv \
	${1}.${2}.metrichor+nanocall~${3}.${mapper}~${mapper_opts}.map_pos_table.tsv \
	${1}.${2}.metrichor+nanocall~${3}.${mapper}~${mapper_opts}.params_table.tsv))
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
	${1}.${2}.summary.${3}.map_pos.tsv \
	${1}.${2}.summary.${3}.errors.tsv \
	${1}.${2}.summary.${3}.runtime.tsv
${1}.${2}.summary.${3}.errors.tsv: \
	$(foreach nanocall_opts,$(call get_pack_nanocall_opt_list,${3}),\
	${1}.${2}.metrichor+nanocall~${nanocall_opts}.bwa~ont2d.error_table.tsv)
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	${ROOT_DIR}/error-summary $$^ >$$@ 2>.$$@.log
${1}.${2}.summary.${3}.map_pos.tsv: \
	$(foreach nanocall_opts,$(call get_pack_nanocall_opt_list,${3}),\
	${1}.${2}.metrichor+nanocall~${nanocall_opts}.bwa~ont2d.map_pos_table.tsv)
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	${ROOT_DIR}/map-pos-summary $$^ >$$@ 2>.$$@.log
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