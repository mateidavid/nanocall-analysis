ifndef ROOT_DIR
$(error Do not use this makefile directly)
endif

EXPORT_FORMATS = pdf eps
EXPORT_TARGETS = figures tables
FIGURES_DPI = 350

TABLE_MAIN_DATASUBSETS = $(call keymap_val,export|table|main|dss)
TABLE_MAIN_R9_DATASUBSETS = $(call keymap_val,export|table|main_r9|dss)
TABLE_TRAIN_STOP_DATASUBSETS = $(call keymap_val,export|table|train_stop|dss)
TABLE_DEFAULT_TRANSITIONS_DATASUBSETS = $(call keymap_val,export|table|default_transitions|dss)

.PHONY: \
	figures $(foreach fmt,${EXPORT_FORMATS},figures-${fmt}) \
	tables $(foreach tb,$(call keymap_key_list,export|table),table-${tb})

figures: $(foreach fmt,${EXPORT_FORMATS},figures-${fmt})
tables: $(foreach tb,$(call keymap_key_list,export|table),table-${tb})

exports:
	mkdir -p exports

define make_table
# ${1}: table_name
# ${2}: table arg
#table-${1}: exports/table_${1}_$(subst .,_,${2}).tex
table-${1}: exports/table_${1}.tex
endef
#$(foreach tb,$(call keymap_key_list,export|table),\
#$(foreach tb_arg,$(call keymap_val,export|table|${tb}|dss),\
#$(eval $(call make_table,${tb},${tb_arg}))))
$(foreach tb,$(call keymap_key_list,export|table),\
$(eval $(call make_table,${tb})))

define make_table_main
# 1: ds
# 2: ss
exports/table_main_${1}_${2}.tex: \
	${1}.${2}.summary.main.mapping.tsv \
	${1}.${2}.summary.main.runtime.tsv \
	| exports
	SGE_RREQ="-N $(subst /,_,$$@) -l h_tvmem=10G" :; \
	{ \
	  ROOT_DIR="${ROOT_DIR}" PYTHON3=${PYTHON3} ${ROOT_DIR}/opt-pack-tex-summary $$^ | \
	  column -t; \
	} >$$@ 2>.$$(patsubst exports/%,%,$$@).log
endef
$(foreach dss,${DATASUBSETS},\
$(foreach ds,$(call get_dss_ds,${dss}),\
$(foreach ss,$(call get_dss_ss,${dss}),\
$(eval $(call make_table_main,${ds},${ss})))))

exports/table_main.tex: \
	$(foreach dss,$(call keymap_val,export|table|main|dss),\
	${dss}.summary.main.mapping.tsv ${dss}.summary.main.runtime.tsv) \
	| exports
	SGE_RREQ="-N $(subst /,_,$@) -l h_tvmem=10G" \
	ROOT_DIR="${ROOT_DIR}" PYTHON3=${PYTHON3} ${ROOT_DIR}/make-table-main \
	  $(foreach dss,$(call keymap_val,export|table|main|dss),\
	  --input ${dss}.summary.main.{mapping,runtime}.tsv) \
	  >$@ 2>>.$(patsubst exports/%,%,$@).log

exports/table_main_aux_rt.tex: \
	$(foreach arg,$(call keymap_val,export|table|main_aux_rt|dss),\
	$(foreach ds,$(word 1,$(subst ., ,${arg})),\
	$(foreach ss1,$(word 2,$(subst ., ,${arg})),\
	$(foreach ss2,$(word 3,$(subst ., ,${arg})),\
	${ds}.${ss1}.summary.main.mapping.tsv ${ds}.${ss2}.summary.main.runtime.tsv)))) \
	| exports
	SGE_RREQ="-N $(subst /,_,$@) -l h_tvmem=10G" \
	ROOT_DIR="${ROOT_DIR}" PYTHON3=${PYTHON3} ${ROOT_DIR}/make-table-main \
	  $(foreach arg,$(call keymap_val,export|table|main_aux_rt|dss),\
	  $(foreach ds,$(word 1,$(subst ., ,${arg})),\
	  $(foreach ss1,$(word 2,$(subst ., ,${arg})),\
	  $(foreach ss2,$(word 3,$(subst ., ,${arg})),\
	  --input ${ds}.${ss1}.summary.main.mapping.tsv ${ds}.${ss2}.summary.main.runtime.tsv)))) \
	  >$@ 2>>.$(patsubst exports/%,%,$@).log

exports/table_default_transitions.tex: \
	$(foreach dss,$(call keymap_val,export|table|default_transitions|dss),\
	${dss}.summary.default_transitions.mapping.tsv) \
	| exports
	SGE_RREQ="-N $(subst /,_,$@) -l h_tvmem=10G" \
	ROOT_DIR="${ROOT_DIR}" PYTHON3=${PYTHON3} ${ROOT_DIR}/make-table-default-transitions \
	  $(foreach dss,$(call keymap_val,export|table|default_transitions|dss),\
	  ${dss}.summary.default_transitions.mapping.tsv) \
	  >$@ 2>>.$(patsubst exports/%,%,$@).log

exports/table_train_stop.tex: \
	$(foreach dss,$(call keymap_val,export|table|train_stop|dss),\
	${dss}.summary.train_stop.mapping.tsv ${dss}.summary.train_stop.runtime.tsv) \
	| exports
	SGE_RREQ="-N $(subst /,_,$@) -l h_tvmem=10G" \
	ROOT_DIR="${ROOT_DIR}" PYTHON3=${PYTHON3} ${ROOT_DIR}/make-table-train-stop \
	  $(foreach dss,$(call keymap_val,export|table|train_stop|dss),\
	  ${dss}.summary.train_stop.{mapping,runtime}.tsv) \
	  >$@ 2>>.$(patsubst exports/%,%,$@).log

exports/table_summary.tex: \
	$(foreach dss,$(call keymap_val,export|table|summary|dss),\
	${dss}.summary.main.mapping.tsv) \
	| exports
	SGE_RREQ="-N $(subst /,_,$@) -l h_tvmem=10G" \
	ROOT_DIR="${ROOT_DIR}" PYTHON3=${PYTHON3} ${ROOT_DIR}/make-table-summary $^ \
	  >$@ 2>>.$(patsubst exports/%,%,$@).log

define make_detailed_figures
# 1: output format
figures-${1}: exports/figure_scale.${1}
exports/figure_scale.${1}: \
	$(foreach rp,${DETAILED_FIGURES_RUNS},${rp}.full_table.tsv) \
	| exports
	SGE_RREQ="-N $(subst /,_,$$@) -l h_tvmem=10G" :; \
	{ \
	  cd exports && \
	  ${PYTHON3} ${ROOT_DIR}/make-plots --format "${1}" --dpi ${FIGURES_DPI} \
	    $(foreach rp,${DETAILED_FIGURES_RUNS},-d "$(call get_ds_name,$(word 1,$(subst ., ,${rp})))" ${PWD}/${rp}.full_table.tsv); \
	}
endef
$(foreach fmt,${EXPORT_FORMATS},$(eval $(call make_detailed_figures,${fmt})))
