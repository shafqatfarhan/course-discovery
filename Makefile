.DEFAULT_GOAL := help
NODE_BIN=$(CURDIR)/node_modules/.bin
TOX := tox

.PHONY: accept clean clean_static check_keywords detect_changed_source_translations extract_translations \
	help html_coverage migrate open-devstack production-requirements pull_translations quality requirements.js \
	requirements.python requirements start-devstack static stop-devstack test docs static.dev static.watch

include .ci/docker.mk


# Generates a help message. Borrowed from https://github.com/pydanny/cookiecutter-djangopackage.
help: ## Display this help message
	@echo "Please use \`make <target>\` where <target> is one of"
	@perl -nle'print $& if m{^[\.a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m  %-25s\033[0m %s\n", $$1, $$2}'

static: ## Gather all static assets for production
	$(NODE_BIN)/webpack --config webpack.config.js --progress
	python manage.py collectstatic -v 0 --noinput

static.dev:
	$(NODE_BIN)/webpack --config webpack.config.js --progress

static.watch:
	$(NODE_BIN)/webpack --config webpack.config.js --progress --watch

clean_static: ## Remove all generated static files
	rm -rf course_discovery/assets/ course_discovery/static/bundles/

clean: ## Delete generated byte code and coverage reports
	find . -name '*.pyc' -delete
	coverage erase

requirements.js: ## Install JS requirements for local development
	npm install
	$(NODE_BIN)/bower install --allow-root

requirements.python: ## Install Python requirements for local development.
	pip install -r requirements/local.txt -r requirements/django.txt

requirements: requirements.js requirements.python ## Install Python and JS requirements for local development

production-requirements: ## Install Python and JS requirements for production
	pip install -r requirements.txt
	npm install --production
	$(NODE_BIN)/bower install --allow-root --production

COMMON_CONSTRAINTS_TXT=requirements/common_constraints.txt
.PHONY: $(COMMON_CONSTRAINTS_TXT)
$(COMMON_CONSTRAINTS_TXT):
	wget -O "$(@)" https://raw.githubusercontent.com/edx/edx-lint/master/edx_lint/files/common_constraints.txt || touch "$(@)"


upgrade: $(COMMON_CONSTRAINTS_TXT)
	sed 's/pyjwt\[crypto\]<2.0.0//g' requirements/common_constraints.txt > requirements/common_constraints.tmp
	mv requirements/common_constraints.tmp requirements/common_constraints.txt
	sed 's/social-auth-core<4.0.3//g' requirements/common_constraints.txt > requirements/common_constraints.tmp
	mv requirements/common_constraints.tmp requirements/common_constraints.txt
	sed 's/edx-auth-backends<4.0.0//g' requirements/common_constraints.txt > requirements/common_constraints.tmp
	mv requirements/common_constraints.tmp requirements/common_constraints.txt
	sed 's/edx-drf-extensions<7.0.0//g' requirements/common_constraints.txt > requirements/common_constraints.tmp
	mv requirements/common_constraints.tmp requirements/common_constraints.txt
	sed 's/Django<2.3//g' requirements/common_constraints.txt > requirements/common_constraints.tmp
	mv requirements/common_constraints.tmp requirements/common_constraints.txt
	pip install -q -r requirements/pip_tools.txt
	pip-compile --upgrade -o requirements/pip_tools.txt requirements/pip_tools.in
	pip-compile --upgrade -o requirements/docs.txt requirements/docs.in
	pip-compile --upgrade -o requirements/local.txt requirements/local.in
	pip-compile --upgrade -o requirements/production.txt requirements/production.in
	# Let tox control the Django version for tests
	grep -e "^django==" requirements/local.txt > requirements/django.txt
	sed -i.tmp '/^[dD]jango==/d' requirements/local.txt
	rm -rf requirements/local.txt.tmp
	chmod a+rw requirements/*.txt

test: clean ## Run tests and generate coverage report
	## The node_modules .bin directory is added to ensure we have access to Geckodriver.
	PATH="$(NODE_BIN):$(PATH)" $(TOX)

quality: ## Run pycodestyle and pylint
	isort --check-only --diff --recursive acceptance_tests/ course_discovery/
	pycodestyle --config=.pycodestyle acceptance_tests course_discovery *.py
	PYTHONPATH=./course_discovery/apps pylint --rcfile=pylintrc acceptance_tests course_discovery *.py

validate: quality test ## Run tests and quality checks

migrate: ## Apply database migrations
	python manage.py migrate --noinput
	python manage.py install_es_indexes

html_coverage: ## Generate and view HTML coverage report
	coverage html && open htmlcov/index.html

# This Make target should not be removed since it is relied on by a Jenkins job (`edx-internal/tools-edx-jenkins/translation-jobs.yml`), using `ecommerce-scripts/transifex`.
extract_translations: ## Extract strings to be translated, outputting .po and .mo files
	# NOTE: We need PYTHONPATH defined to avoid ImportError(s) on CI.
	cd course_discovery && PYTHONPATH="..:${PYTHONPATH}" django-admin.py makemessages -l en -v1 --ignore="assets/*" --ignore="static/bower_components/*" --ignore="static/build/*" -d django
	cd course_discovery && PYTHONPATH="..:${PYTHONPATH}" django-admin.py makemessages -l en -v1 --ignore="assets/*" --ignore="static/bower_components/*" --ignore="static/build/*" -d djangojs
	cd course_discovery && PYTHONPATH="..:${PYTHONPATH}" i18n_tool dummy
	cd course_discovery && PYTHONPATH="..:${PYTHONPATH}" django-admin.py compilemessages

# This Make target should not be removed since it is relied on by a Jenkins job (`edx-internal/tools-edx-jenkins/translation-jobs.yml`), using `ecommerce-scripts/transifex`.
pull_translations: ## Pull translations from Transifex
	tx pull -a -f --mode reviewed --minimum-perc=1

# This Make target should not be removed since it is relied on by a Jenkins job (`edx-internal/tools-edx-jenkins/translation-jobs.yml`), using `ecommerce-scripts/transifex`.
push_translations: ## Push source translation files (.po) to Transifex
	tx push -s

start-devstack: ## Run a local development copy of the server
	docker-compose up

stop-devstack: ## Shutdown the local development server
	docker-compose down

open-devstack: ## Open a shell on the server started by start-devstack
	docker-compose up -d
	docker exec -it course-discovery env TERM=$(TERM) /edx/app/discovery/devstack.sh open

accept: ## Run acceptance tests
	nosetests --with-ignore-docstrings -v acceptance_tests

# This Make target should not be removed since it is relied on by a Jenkins job (`edx-internal/tools-edx-jenkins/translation-jobs.yml`), using `ecommerce-scripts/transifex`.
detect_changed_source_translations: ## Check if translation files are up-to-date
	cd course_discovery && i18n_tool changed

docs:
	cd docs && make html

check_keywords: ## Scan the Django models in all installed apps in this project for restricted field names
	python manage.py check_reserved_keywords --override_file db_keyword_overrides.yml

docker_build:
	docker build . -f Dockerfile --target app -t openedx/discovery
	docker build . -f Dockerfile --target newrelic -t openedx/discovery:latest-newrelic

docker_tag: docker_build
	docker tag openedx/discovery openedx/discovery:${GITHUB_SHA}
	docker tag openedx/discovery:latest-newrelic openedx/discovery:${GITHUB_SHA}-newrelic

docker_auth:
	echo "$$DOCKERHUB_PASSWORD" | docker login -u "$$DOCKERHUB_USERNAME" --password-stdin

docker_push: docker_tag docker_auth ## push to docker hub
	docker push 'openedx/discovery:latest'
	docker push "openedx/discovery:${GITHUB_SHA}"
	docker push 'openedx/discovery:latest-newrelic'
	docker push "openedx/discovery:${GITHUB_SHA}-newrelic"

migration_linter:
	python manage.py lintmigrations
