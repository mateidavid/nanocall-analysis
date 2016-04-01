ifndef ROOT_DIR
$(error Do not use this makefile directly)
endif

.PHONY: \
	figures $(foreach fmt,${EXPORT_FORMATS},figures-${fmt}) \
	tables table-main table-default-transitions table-train-stop

EXPORT_FORMATS = pdf eps
EXPORT_TARGETS = figures tables
FIGURES_DPI = 350

figures: $(foreach fmt,${EXPORT_FORMATS},figures-${fmt})

TABLE_MAIN_DATASUBSETS = $(call keymap_val,export|table|main|dss)
TABLE_TRAIN_STOP_DATASUBSETS = $(call keymap_val,export|table|train_stop|dss)
TABLE_DEFAULT_TRANSITIONS_DATASUBSETS = $(call keymap_val,export|table|default_transitions|dss)

tables: table-main table-train-stop table-default-transitions

exports:
	mkdir -p exports

define make_table
# ${1}: table_name
# ${2}: dss list
table-${1}: \
	$(foreach dss,${2},\
	$(foreach ds,$(call get_dss_ds,${dss}),\
	$(foreach ss,$(call get_dss_ss,${dss}),\
	exports/table_$(subst -,_,${1})_${ds}_${ss}.tex)))
endef
$(eval $(call make_table,main,${TABLE_MAIN_DATASUBSETS}))
$(eval $(call make_table,train-stop,${TABLE_TRAIN_STOP_DATASUBSETS}))
$(eval $(call make_table,default-transitions,${TABLE_DEFAULT_TRANSITIONS_DATASUBSETS}))

define make_table_main
# 1: ds
# 2: ss
exports/table_main_${1}_${2}.tex: \
	${1}.${2}.summary.main.map_pos.tsv \
	${1}.${2}.summary.main.errors.tsv \
	${1}.${2}.summary.main.runtime.tsv \
	| exports
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	{ \
	  ROOT_DIR="${ROOT_DIR}" PYTHON3=${PYTHON3} ${ROOT_DIR}/opt-pack-tex-summary $$^ | \
	  column -t; \
	} >$$@ 2>.$$(patsubst exports/%,%,$$@).log
endef
$(foreach dss,${DATASUBSETS},\
$(foreach ds,$(call get_dss_ds,${dss}),\
$(foreach ss,$(call get_dss_ss,${dss}),\
$(eval $(call make_table_main,${ds},${ss})))))

define make_table_train_stop
# 1: ds
# 2: ss
exports/table_train_stop_${1}_${2}.tex: \
	${1}.${2}.summary.train_stop.map_pos.tsv \
	${1}.${2}.summary.train_stop.errors.tsv \
	${1}.${2}.summary.train_stop.runtime.tsv \
	| exports
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	{ \
	  ROOT_DIR="${ROOT_DIR}" PYTHON3=${PYTHON3} ${ROOT_DIR}/opt-pack-tex-summary $$^ | \
	  cut -f 3- | \
	  column -t; \
	} >$$@ 2>.$$(patsubst exports/%,%,$$@).log
endef
$(foreach dss,${DATASUBSETS},\
$(foreach ds,$(call get_dss_ds,${dss}),\
$(foreach ss,$(call get_dss_ss,${dss}),\
$(eval $(call make_table_train_stop,${ds},${ss})))))

define make_table_default_transitions
# 1: ds
# 2: ss
exports/table_default_transitions_${1}_${2}.tex: \
	${1}.${2}.summary.default_transitions.map_pos.tsv \
	${1}.${2}.summary.default_transitions.errors.tsv \
	${1}.${2}.summary.default_transitions.runtime.tsv \
	| exports
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	{ \
	  ROOT_DIR="${ROOT_DIR}" PYTHON3=${PYTHON3} ${ROOT_DIR}/opt-pack-tex-summary $$^ | \
	  cut -f 3-11,14 | \
	  column -t; \
	} >$$@ 2>.$$(patsubst exports/%,%,$$@).log
endef
$(foreach dss,${DATASUBSETS},\
$(foreach ds,$(call get_dss_ds,${dss}),\
$(foreach ss,$(call get_dss_ss,${dss}),\
$(eval $(call make_table_default_transitions,${ds},${ss})))))

define make_detailed_figures
# 1: output format
figures-${1}: exports/figure_scale.${1}
exports/figure_scale.${1}: \
	$(foreach rp,${DETAILED_FIGURES_RUNS},${rp}.bam.summary.tsv ${rp}.params_table.tsv) \
	| exports
	SGE_RREQ="-N $$@ -l h_tvmem=10G" :; \
	{ \
	  cd exports && \
	  ${PYTHON3} ${ROOT_DIR}/make-plots --format "${1}" --dpi ${FIGURES_DPI} \
	    $(foreach rp,${DETAILED_FIGURES_RUNS},-d "$(call get_ds_name,$(word 1,$(subst ., ,${rp})))" ${PWD}/${rp}.{bam.summary,params_table}.tsv); \
	}
endef
$(foreach fmt,${EXPORT_FORMATS},$(eval $(call make_detailed_figures,${fmt})))
