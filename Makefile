export KODI_HOME := $(CURDIR)/tests/home
export KODI_INTERACTIVE := 0
PYTHON := python
KODI_PYTHON_ABIS := 3.0.0 2.26.0

# Collect information to build as sensible package name
name = $(shell xmllint --xpath 'string(/addon/@id)' addon.xml)
version = $(shell xmllint --xpath 'string(/addon/@version)' addon.xml)
git_branch = $(shell git rev-parse --abbrev-ref HEAD)
git_hash = $(shell git rev-parse --short HEAD)

ifdef release
	zip_name = $(name)-$(version).zip
else
	zip_name = $(name)-$(version)-$(git_branch)-$(git_hash).zip
endif

include_files = addon_entry.py addon.xml CHANGELOG.md LICENSE README.md resources/ service_entry.py
include_paths = $(patsubst %,$(name)/%,$(include_files))
exclude_files = \*.new \*.orig \*.pyc \*.pyo

languages = $(filter-out en_gb, $(patsubst resources/language/resource.language.%, %, $(wildcard resources/language/*)))

all: check test build
zip: build

check: check-pylint check-tox check-translations

check-pylint:
	@echo ">>> Running pylint checks"
	@$(PYTHON) -m pylint *.py resources/lib/ tests/

check-tox:
	@echo ">>> Running tox checks"
	@$(PYTHON) -m tox -q

check-translations:
	@echo ">>> Running translation checks"
	@$(foreach lang,$(languages), \
		msgcmp resources/language/resource.language.$(lang)/strings.po resources/language/resource.language.en_gb/strings.po; \
	)
	@tests/check_for_unused_translations.py

check-addon: clean build
	@echo ">>> Running addon checks"
	$(eval TMPDIR := $(shell mktemp -d))
	@unzip ../${zip_name} -d ${TMPDIR}
	cd ${TMPDIR} && kodi-addon-checker --branch=leia
	@rm -rf ${TMPDIR}

codefix:
	@isort -l 160 resources/

test: test-unit

test-unit:
	@echo ">>> Running unit tests"
	@$(PYTHON) -m pytest tests

clean:
	@find . -name '*.py[cod]' -type f -delete
	@find . -name '__pycache__' -type d -delete
	@rm -rf .pytest_cache/ .tox/ tests/cdm tests/userdata/temp
	@rm -f *.log .coverage

build: clean
	@echo ">>> Building package"
	@rm -f ../$(zip_name)
	cd ..; zip -r $(zip_name) $(include_paths) -x $(exclude_files)
	@echo "Successfully wrote package as: ../$(zip_name)"

release:
ifneq ($(release),)
	# Set version
	@echo "cd /addon/@version\nset $$release\nsave\nbye" | xmllint --shell addon.xml > /dev/null

	# Update changelog
	@github_changelog_generator -u add-ons -p plugin.video.streamz --no-issues --future-release $(release)

	# Next steps to release:
	# git add . && git commit -m "Prepare for $(release)" && git push
	# git tag $(release) && git push --tags
else
	@echo "Usage: make release release=v1.0.0"
endif

multizip: clean
	@-$(foreach abi,$(KODI_PYTHON_ABIS), \
		echo "cd /addon/requires/import[@addon='xbmc.python']/@version\nset $(abi)\nsave\nbye" | xmllint --shell addon.xml; \
		matrix=$(findstring $(abi), $(word 1,$(KODI_PYTHON_ABIS))); \
		if [ $$matrix ]; then version=$(version)+matrix.1; else version=$(version); fi; \
		echo "cd /addon/@version\nset $$version\nsave\nbye" | xmllint --shell addon.xml; \
		make build; \
	)
