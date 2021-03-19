# Ontology for Biobanking Makefile
# Jie Zheng
#
# This Makefile is used to build artifacts
# for the Ontology for Biobanking (OBIB)
#

### Configuration
#
# prologue:
# <http://clarkgrubb.com/makefile-style-guide#toc2>

MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:

### Definitions

SHELL   := /bin/bash
OBO     := http://purl.obolibrary.org/obo
OBIB    := $(OBO)/OBIB_
DEV     := $(OBO)/obib/dev
TODAY   := $(shell date +%Y-%m-%d)


### Directories
#
# This is a temporary place to put things.
build:
	mkdir -p $@


### ROBOT
#
# We use the official release version of ROBOT
build/robot.jar: | build
	@echo "Getting ROBOT" && \
	curl -L -o $@ https://github.com/ontodev/robot/releases/download/v1.8.1/robot.jar

ROBOT := java -jar build/robot.jar

### Imports
#
# Use Ontofox to regenerate fresh import-OBO file
.PHONY: src/imports/import_OBO.owl
src/imports/import_OBO.owl:
	@echo "Generating $@" && \
	curl -s -F file=src/external/ontoFox_input/OBO_input.txt http://ontofox.hegroup.org/service.php > src/imports/import_OBO.owl


### Build
#
# Here we create a standalone OWL file appropriate for release.
# This involves merging, reasoning, annotating,
# and removing any remaining import declarations.
build/obib_merged.owl: src/obib_dev.owl | build/robot.jar build
	$(ROBOT) merge \
	--input $< \
	annotate \
	--ontology-iri "$(OBO)/obib/obib_merged.owl" \
	--version-iri "$(OBO)/obib/$(TODAY)/obib_merged.owl" \
	--annotation owl:versionInfo "$(TODAY)" \
	--output build/obib_merged.tmp.owl
	sed '/http:\/\/www\.w3\.org\/1999\/02\/22-rdf-syntax-ns#type/d' build/obib_merged.tmp.owl > build/obib_merged.tmp2.owl
	sed '/<owl:imports/d' build/obib_merged.tmp2.owl > $@
	rm build/obib_merged.tmp.owl
	rm build/obib_merged.tmp2.owl

obib.owl: build/obib_merged.owl
	$(ROBOT) reason \
	--input $< \
	--reasoner HermiT \
	annotate \
	--ontology-iri "$(OBO)/obib.owl" \
	--version-iri "$(OBO)/obib/$(TODAY)/obib.owl" \
	--annotation owl:versionInfo "$(TODAY)" \
	--output $@

test_report.tsv: build/obib_merged.owl
	$(ROBOT) report \
	--input $< \
        --fail-on none \
	--output $@

### Test
#
# Run main tests
MERGED_VIOLATION_QUERIES := $(wildcard src/sparql/*-violation.rq)

build/terms-report.csv: build/obib_merged.owl src/sparql/terms-report.rq | build
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/obib-previous-release.owl: | build
	curl -L -o $@ "http://purl.obolibrary.org/obo/obib.owl"

build/released-entities.tsv: build/obib-previous-release.owl src/sparql/get-obib-entities.rq | build/robot.jar
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/current-entities.tsv: build/obib_merged.owl src/sparql/get-obib-entities.rq | build/robot.jar
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/dropped-entities.tsv: build/released-entities.tsv build/current-entities.tsv
	comm -23 $^ > $@

# Run all validation queries and exit on error.
.PHONY: verify
verify: verify-merged verify-entities

# Run validation queries on obib_merged and exit on error.
.PHONY: verify-merged
verify-merged: build/obib_merged.owl $(MERGED_VIOLATION_QUERIES) | build/robot.jar
	$(ROBOT) verify --input $< --output-dir build \
	--queries $(MERGED_VIOLATION_QUERIES)

# Check if any entities have been dropped and exit on error.
.PHONY: verify-entities
verify-entities: build/dropped-entities.tsv
	@echo $(shell < $< wc -l) " obib IRIs have been dropped"
	@! test -s $<

# Run a Hermit reasoner to find inconsistencies
.PHONY: reason
reason: build/obib_merged.owl | build/robot.jar
	$(ROBOT) reason --input $< --reasoner HermiT

.PHONY: test
test: reason verify


### 
#
# Full build
.PHONY: all
all: test obib.owl build/terms-report.csv

# Remove generated files
.PHONY: clean
clean:
	rm -rf build

# Check for problems such as bad line-endings
.PHONY: check
check:
	src/scripts/check-line-endings.sh tsv

# Fix simple problems such as bad line-endings
.PHONY: fix
fix:
	src/scripts/fix-eol-all.sh
