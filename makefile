#!make
SHELL = /bin/bash -o pipefail
export DOCKER_BUILDKIT = 1
export COMPOSE_DOCKER_CLI_BUILD = 1

browse:
	sensible-browser --new-tab http://0.0.0.0:3080/ </dev/null >/dev/null 2>&1 & disown

# ==============================================================================
# Building containers

all: api ui

api:
	docker build \
		-f deployment/docker/dockerfile.travel-api \
		-t travel-api-amd64:1.0 \
		--build-arg VCS_REF=$$(git rev-parse HEAD) \
		--build-arg BUILD_DATE=$$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
		.

ui:
	docker build \
		-f deployment/docker/dockerfile.travel-ui \
		-t travel-ui-amd64:1.0 \
		--build-arg VCS_REF=$$(git rev-parse HEAD) \
		--build-arg BUILD_DATE=$$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
		.

# ==============================================================================
# Running from within docker compose

run: compose-up seed browse

compose-config:
	docker-compose -f deployment/docker/docker-compose.yaml \
	-f deployment/docker/docker-compose.override.yaml \
	config

compose-up:
	docker-compose -f deployment/docker/docker-compose.yaml \
	-f deployment/docker/docker-compose.override.yaml \
	up --detach --remove-orphans

compose-down:
	docker-compose -f deployment/docker/docker-compose.yaml \
	-f deployment/docker/docker-compose.override.yaml \
	down --remove-orphans

compose-logs:
	docker-compose -f deployment/docker/docker-compose.yaml \
	-f deployment/docker/docker-compose.override.yaml \
	logs -f

# ==============================================================================
# Running from within k8s/dev

kind-up:
	$(shell go env GOPATH)/bin/kind create cluster --image kindest/node:v1.20.2 --name dgraph-travel-cluster --config deployment/k8s/dev/kind-config.yaml

kind-down:
	$(shell go env GOPATH)/bin/kind delete cluster --name dgraph-travel-cluster

kind-load:
	$(shell go env GOPATH)/bin/kind load docker-image travel-api-amd64:1.0 --name dgraph-travel-cluster
	$(shell go env GOPATH)/bin/kind load docker-image travel-ui-amd64:1.0 --name dgraph-travel-cluster

kind-list:
	@docker exec -it dgraph-travel-cluster-control-plane crictl images

kind-services:
	$(shell go env GOPATH)/bin/kustomize build deployment/k8s/dev | kubectl apply -f -

kind-api: api
	$(shell go env GOPATH)/bin/kind load docker-image travel-api-amd64:1.0 --name dgraph-travel-cluster
	kubectl delete pods -lapp=travel

kind-ui: ui
	$(shell go env GOPATH)/bin/kind load docker-image travel-ui-amd64:1.0 --name dgraph-travel-cluster
	kubectl delete pods -lapp=travel

kind-logs:
	kubectl logs -lapp=travel --all-containers=true -f

kind-status:
	kubectl get nodes
	kubectl get pods --watch

kind-status-full:
	kubectl describe pod -lapp=travel

kind-delete:
	$(shell go env GOPATH)/bin/kustomize build deployment/k8s/dev | kubectl delete -f -

kind-schema:
	go run app/travel-admin/main.go --custom-functions-upload-feed-url=http://localhost:3000/v1/feed/upload schema

kind-seed: kind-schema
	go run app/travel-admin/main.go seed 

# ==============================================================================
# Running from within the local with Slash

slash-run: slash-up seed slash-browse

slash-conf:
	docker-compose -f deployment/docker/docker-compose-slash.yaml config

slash-up:
	docker-compose -f deployment/docker/docker-compose-slash.yaml up --detach --remove-orphans

slash-down:
	docker-compose -f deployment/docker/docker-compose-slash.yaml down --remove-orphans

slash-browse:
	python -m webbrowser "http://localhost"

slash-logs:
	docker-compose -f deployment/docker/docker-compose-slash.yaml logs -f

# ==============================================================================
# Running Local

local-run: local-up seed browse

local-up:
	go run app/travel-api/main.go &> api.log &
	cd app/travel-ui; \
	go run main.go &> ../../ui.log &

API := $(shell lsof -i tcp:4000 | cut -c9-13 | grep "[0-9]")
UI := $(shell lsof -i tcp:4080 | cut -c9-13 | grep "[0-9]")

ps:
	lsof -i tcp:4000; \
	lsof -i tcp:4080

local-down:
	kill -15 $(API); \
	kill -15 $(UI); \
	rm *.log

api-logs:
	tail -F api.log

ui-logs:
	tail -F ui.log

# ==============================================================================
# Administration

schema:
	go run app/travel-admin/main.go schema

seed: schema
	go run app/travel-admin/main.go seed

# Running tests within the local computer

test:
	go test ./... -count=1
	$(shell go env GOPATH)/bin/staticcheck ./...

# Modules support

deps-reset:
	git checkout -- go.mod
	go mod tidy
	go mod vendor

tidy:
	go mod tidy
	go mod vendor

deps-upgrade:
	go get -u -t -d -v ./...
	go mod tidy
	go mod vendor

deps-cleancache:
	go clean -modcache

# ==============================================================================
# Docker support

containers := $$(docker ps -aq --filter name=travel-ui --filter name=travel-api --filter name=dgraph-alpha --filter name=dgraph-zero)

down-local:
	@docker container stop ${containers}
	@docker container rm ${containers}

clean:
	docker system prune -f

logs-local:
	@docker container logs -f $$(docker ps -aq --filter name=travel-api)

# ==============================================================================
# Git support

install-hooks:
	cp -r .githooks/pre-commit .git/hooks/pre-commit

remove-hooks:
	rm .git/hooks/pre-commit