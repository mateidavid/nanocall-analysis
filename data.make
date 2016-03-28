ifndef ROOT_DIR
$(error Do not use this makefile directly)
endif

DATA_TARGETS = \
	$(foreach ref,${REFERENCES},${ref}--reference ${ref}--bwa-index) \
	$(foreach ds,${DATASETS},${ds}) \
	$(foreach dss,${DATASUBSETS},${dss}.fofn)

#####################
#
# References
#
# Human
#
.PHONY: human--reference
human--reference: human.fa human.fa.fai
${DATA_DIR}/human.fa:
	mkdir -p ${DATA_DIR}; \
	url="$(call keymap_val,reference|human|url)"; \
	cache_url="${CACHE_DIR}/$$(basename "$$url")"; \
	md5sum="$(call keymap_val,reference|human|md5sum)"; \
	for f in "$$url" "$$cache_url"; do \
	  if [ "$$f" ] && [ -r "$$f" ]; then \
	    ln -sf "$$(readlink -e "$$f")" $@; \
	    break; \
	  fi; \
	done; \
	if ! [ -r $@ ]; then \
	  wget -L "$$url" -O "$$cache_url"; \
	  ! [ "$$md5sum" ] || [ "$$(md5sum <"$$cache_url" | awk '{print $$1}')" = "$$md5sum" ]; \
	  zcat -f "$$cache_url" >$@; \
	fi
human.fa: ${HUMAN_REFERENCE}
	ln -sf $< $@
#
# Ecoli
#
.PHONY: ecoli--reference
ecoli--reference: ecoli.fa ecoli.fa.fai
${DATA_DIR}/ecoli.fa:
	mkdir -p ${DATA_DIR}; \
	url="$(call keymap_val,reference|ecoli|url)"; \
	cache_url="${CACHE_DIR}/$$(basename "$$url")"; \
	md5sum="$(call keymap_val,reference|ecoli|md5sum)"; \
	for f in "$$url" "$$cache_url"; do \
	  if [ "$$f" ] && [ -r "$$f" ]; then \
	    ln -sf "$$(readlink -e "$$f")" $@; \
	    break; \
	  fi; \
	done; \
	if [ ! -r $@ ]; then \
	  wget -L "$$url" -O "$$cache_url"; \
	  [ ! "$$md5sum" ] || [ "$$(md5sum <"$$cache_url" | awk '{print $$1}')" = "$$md5sum" ]; \
	  zcat -f "$$cache_url" >$@; \
	fi
ecoli.fa: ${ECOLI_REFERENCE}
	ln -sf $< $@
#
# Fasta indexes
#
define make_fa_index
${1}.fa.fai: ${1}.fa | samtools.version
	if [ -r "$$$$(readlink -e "${1}.fa").fai" ]; then \
	  ln -sf "$$$$(readlink -e "${1}.fa").fai" $$@; \
	else \
	  ${SAMTOOLS} faidx ${1}; \
	fi
endef
$(foreach ref,${REFERENCES},\
$(eval $(call make_fa_index,${ref})))
#
# BWA index
#
BWA_INDEX_EXT := bwt pac ann amb sa
define make_bwa_index
.PHONY: ${1}--bwa-index
${1}--bwa-index: ${1}--reference $(foreach ext,${BWA_INDEX_EXT},${1}.fa.${ext})
${1}.fa.bwt: ${1}.fa | bwa.version
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
$(foreach ref,${REFERENCES},$(eval $(call make_bwa_index,${ref})))
#
# Last index
#
LAST_INDEX_EXT := bck des prj sds ssp suf tis
define make_last_index
.PHONY: ${1}--last-index
${1}--last-index: $(foreach ext,${LAST_INDEX_EXT},${1}.fa.lastdb.${ext}) | last.version
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
# parameters:
# 1 = ds name
# 2 = url
# 3 = md5sum
# 4 = dirname
define make_data_dir
${DATA_DIR}/${4}:
	mkdir -p ${DATA_DIR}; \
	first_component="${4}"; \
	first_component=$$$${first_component%%/*}; \
	if [ -d "${2}" ]; then \
	  test "$$$$(basename "${2}")" = "$$$$first_component"; \
	  ln -sf "${2}" ${DATA_DIR}/$$$$first_component; \
	else \
	  cache_url="${CACHE_DIR}/$$$$(basename "${2}")"; \
	  if [ -r "${2}" ]; then \
	    ln -sf "${2}" "$$$$cache_url"; \
	  else \
	    wget -L "${2}" -O "$$$$cache_url"; \
	    test "$$$$(md5sum <"$$$$cache_url" | awk '{print $$$$1}')" = "${3}"; \
	  fi; \
	  tar -xf "$$$$cache_url" -C ${DATA_DIR}; \
	  test -d $$@; \
	fi
${1}: ${DATA_DIR}/${4}
	ln -sf "$$<" $$@
endef
$(foreach ds,${DATASETS},\
$(eval $(call make_data_dir,${ds},$(call keymap_val,dataset|${ds}|url),$(call keymap_val,dataset|${ds}|md5sum),$(call keymap_val,dataset|${ds}|dirname))))

#
# fofn: all
#
define make_all_fofn
${1}.all.fofn: ${1}
	find ${1}/ -name '*.fast5' ! -type d | grep -v "\<raw\>" >$$@
endef
$(foreach ds,${DATASETS},$(eval $(call make_all_fofn,${ds})))
#
# fofn: subsets
#
define make_dss_fofn
${1}.${2}.fofn: ${1}.all.fofn
	cat $$< | eval "$(call keymap_val,subset|${2})" >$$@
endef
$(foreach dss,$(shell echo "${DATASUBSETS}" | tr ' ' '\n' | grep -v "\.all$$" | tr '\n' ' '),\
  $(eval $(call make_dss_fofn,$(call get_dss_ds,${dss}),$(call get_dss_ss,${dss}))))
#
#####################
