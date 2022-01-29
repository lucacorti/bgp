##
# Make utility to automate boring and repetitive commands
#
# @file Makefile
# @version 0.1

all: init
.PHONY: init start up build shell test halt delete

init: up							## Setup application components

start: up							## Start application
	docker-compose exec bgp mix run --no-halt

up:									## Start all services
	docker-compose up -d --remove-orphans

build:								## Build all services containers
	docker-compose build

shell: container-bgp				## Enter into bgp service
	docker-compose exec bgp bash

test: container-bgp					## Execute test suite
	docker-compose exec bgp mix test

halt:								## Shoutdown all services containers
	docker-compose down

delete: halt						## Delete all containers, images and volumes
	@docker images -a | grep "bgp" | awk '{print $3}' | xargs docker rmi -f | docker ps -a | grep "bgp" | awk '{print $1}' | xargs docker rm -v

help:
	@echo "Usage: make [command]"
	@echo "Make utility to automate boring and repetitive commands."
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo

container-%:
	@docker ps -q --no-trunc --filter status=running | grep $$(docker-compose ps -q $*) >/dev/null 2>&1 || docker-compose up -d $*

# end