isDocker := $(shell docker info > /dev/null 2>&1 && echo 1)
isContainerRunning := $(shell docker ps | grep symfony-php > /dev/null 2>&1 && echo 1)
user := $(shell id -u)
group := $(shell id -g)

conf_exists:
ifneq ("$(wildcard .env)","")
include .env
else
	cp .env.dist .env
endif

ifeq ($(isDocker), 1)
	ifeq ($(isContainerRunning), 1)
		DOCKER_COMPOSE := USER_ID=$(user) GROUP_ID=$(group) docker-compose
		DOCKER_EXEC := docker exec -u $(user):$(group) symfony-php
		dr := $(DOCKER_COMPOSE) run --rm
		sf := $(DOCKER_EXEC) php bin/console
		drtest := $(DOCKER_COMPOSE) -f docker-compose.test.yml run --rm
		php := $(DOCKER_EXEC) --no-deps php
	else
		DOCKER_COMPOSE := USER_ID=$(user) GROUP_ID=$(group) docker-compose
		DOCKER_EXEC :=
		sf := php bin/console
		php :=
	endif
else
	DOCKER_EXEC :=
	sf := php bin/console
	php :=
endif

COMPOSER = $(DOCKER_EXEC) composer
CONSOLE = $(DOCKER_COMPOSE) php bin/console

## —— App ————————————————————————————————————————————————————————————————

build-docker: conf_exists
	$(DOCKER_COMPOSE) pull --ignore-pull-failures
	$(DOCKER_COMPOSE) build --no-cache php

up: conf_exists
	@echo "Launching containers from project $(COMPOSE_PROJECT_NAME)..."
	$(DOCKER_COMPOSE) up -d
	$(DOCKER_COMPOSE) ps

stop:
	@echo "Stopping containers from project $(COMPOSE_PROJECT_NAME)..."
	$(DOCKER_COMPOSE) stop
	$(DOCKER_COMPOSE) ps

## —— 🐝 The Symfony Makefile 🐝 ———————————————————————————————————
help: ## Outputs this help screen
	@grep -E '(^[a-zA-Z0-9_-]+:.*?## .*$$)|(^## )' Makefile | awk 'BEGIN {FS = ":.*?## "}{printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'

## —— Composer 🧙‍♂️ ————————————————————————————————————————————————————————————
composer-install: composer.lock ## Install vendors according to the current composer.lock file
	$(COMPOSER) install -n

composer-update: composer.json ## Update vendors according to the composer.json file
	$(COMPOSER) update -w

## —— Symfony ————————————————————————————————————————————————————————————————
cc: ## Apply cache clear
	$(DOCKER_EXEC) sh -c "rm -rf var/cache/*"
	$(sf) cache:clear
	$(DOCKER_EXEC) sh -c "chmod -R 777 var/cache"

doctrine-validate:
	$(sf) doctrine:schema:validate --skip-sync $c

reset-database: drop-database database migrate load-fixtures ## Reset database with migration

database: ## Create database if no exists
	$(sf) doctrine:database:create --if-not-exists

drop-database: ## Drop the database
	$(sf) doctrine:database:drop --force --if-exists

migration: ## Apply doctrine migration
	$(sf) make:migration

migrate: ## Apply doctrine migrate
	$(sf) doctrine:migration:migrate -n --all-or-nothing

load-fixtures: ## Load fixtures
	$(sf) doctrine:fixtures:load -n

generate-jwt:
	$(sf) lexik:jwt:generate-keypair --overwrite -q $c

## —— Tests ✅ ————————————————————————————————————————————————————————————
test-load-fixtures: ## load database schema & fixtures
	$(DOCKER_COMPOSE) sh -c "APP_ENV=test php bin/console doctrine:database:drop --if-exists --force"
	$(DOCKER_COMPOSE) sh -c "APP_ENV=test php bin/console doctrine:database:create --if-not-exists"
	$(DOCKER_COMPOSE) sh -c "APP_ENV=test php bin/console doctrine:migration:migrate -n --all-or-nothing"
	$(DOCKER_COMPOSE) sh -c "APP_ENV=test php bin/console doctrine:fixtures:load -n"

test: phpunit.xml* ## Launch main functional and unit tests, stopped on failure
	$(php) APP_ENV=test ./vendor/bin/simple-phpunit

test-all: phpunit.xml* test-load-fixtures ## Launch main functional and unit tests
	$(php) APP_ENV=test ./vendor/bin/simple-phpunit

test-report: phpunit.xml* test-load-fixtures ## Launch main functionnal and unit tests with report
	$(php) APP_ENV=test ./vendor/bin/simple-phpunit --coverage-text --coverage-clover=coverage.xml

## —— Coding standards ✨ ——————————————————————————————————————————————————————
stan: ## Run PHPStan only
	$(php) ./vendor/bin/phpstan analyse -l 9 src --no-progress -c phpstan.neon --memory-limit 256M

cs-fix: ## Run php-cs-fixer and fix the code.
	$(php) ./vendor/bin/php-cs-fixer fix --allow-risky=yes

cs-dry: ## Dry php-cs-fixer and display code may to be change
	$(php) ./vendor/bin/php-cs-fixer fix --dry-run --allow-risky=yes
