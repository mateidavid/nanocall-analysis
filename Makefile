.SUFFIXES:
MAKEFLAGS += -r
SHELL := /bin/bash
ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# do not leave failed files around
.DELETE_ON_ERROR:
# do not delete intermediate files
#.SECONDARY:
# fake targets
.PHONY: all list clean cleanall help

all:

print-%:
	@echo '$*=$($*)'

help: ## This help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

include ${ROOT_DIR}/common.make
include ${ROOT_DIR}/tools.make
include ${ROOT_DIR}/data.make
include ${ROOT_DIR}/runs.make
include ${ROOT_DIR}/exports.make

all: ${TOOLS_TARGETS} ${EXPORT_TARGETS}

list: print-TOOLS_TARGETS print-DATA_TARGETS print-DATASETS print-DATASUBSETS print-EXPORT_TARGETS

clean:
	@rm -f ${TARGETS}

cleanall: clean
	@rm -f ${SPECIAL_TARGETS}
