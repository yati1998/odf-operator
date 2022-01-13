include hack/make-project-vars.mk
include hack/make-tools.mk
include hack/make-bundle-vars.mk


# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test target.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.DEFAULT_GOAL := help

all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

help: ## Display this help.
	@./hack/make-help.sh $(MAKEFILE_LIST)

##@ Development

manifests: controller-gen update-mgr-env ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases

generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

fmt: ## Run go fmt against code.
	go fmt ./...

vet: ## Run go vet against code.
	go vet ./...

vendor-update: ## Run go mod vendor against code.
	go mod vendor

test: manifests generate fmt vet vendor-update ## Run tests.
	mkdir -p ${ENVTEST_ASSETS_DIR}
	test -f ${ENVTEST_ASSETS_DIR}/setup-envtest.sh || curl -sSLo ${ENVTEST_ASSETS_DIR}/setup-envtest.sh https://raw.githubusercontent.com/kubernetes-sigs/controller-runtime/v0.8.3/hack/setup-envtest.sh
	source ${ENVTEST_ASSETS_DIR}/setup-envtest.sh; fetch_envtest_tools $(ENVTEST_ASSETS_DIR); setup_envtest_env $(ENVTEST_ASSETS_DIR); go test ./... -coverprofile cover.out

define MANAGER_ENV_VARS
OPERATOR_NAMESPACE=$(OPERATOR_NAMESPACE)
ODF_SUBSCRIPTION_NAME=$(ODF_SUBSCRIPTION_NAME)
ODF_SUBSCRIPTION_STARTINGCSV=$(ODF_SUBSCRIPTION_STARTINGCSV)
NOOBAA_SUBSCRIPTION_NAME=$(NOOBAA_SUBSCRIPTION_NAME)
NOOBAA_SUBSCRIPTION_PACKAGE=$(NOOBAA_SUBSCRIPTION_PACKAGE)
NOOBAA_SUBSCRIPTION_CHANNEL=$(NOOBAA_SUBSCRIPTION_CHANNEL)
NOOBAA_SUBSCRIPTION_STARTINGCSV=$(NOOBAA_SUBSCRIPTION_STARTINGCSV)
NOOBAA_SUBSCRIPTION_CATALOGSOURCE=$(NOOBAA_SUBSCRIPTION_CATALOGSOURCE)
NOOBAA_SUBSCRIPTION_CATALOGSOURCE_NAMESPACE=$(NOOBAA_SUBSCRIPTION_CATALOGSOURCE_NAMESPACE)
CSI_ADDONS_SUBSCRIPTION_CATALOGSOURCE=$(CSI_ADDONS_SUBSCRIPTION_CATALOGSOURCE)
CSI_ADDONS_SUBSCRIPTION_CATALOGSOURCE_NAMESPACE=$(CSI_ADDONS_SUBSCRIPTION_CATALOGSOURCE_NAMESPACE)
CSI_ADDONS_SUBSCRIPTION_CHANNEL=$(CSI_ADDONS_SUBSCRIPTION_CHANNEL)
CSI_ADDONS_SUBSCRIPTION_NAME=$(CSI_ADDONS_SUBSCRIPTION_NAME)
CSI_ADDONS_SUBSCRIPTION_PACKAGE=$(CSI_ADDONS_SUBSCRIPTION_PACKAGE)
CSI_ADDONS_SUBSCRIPTION_STARTINGCSV=$(CSI_ADDONS_SUBSCRIPTION_STARTINGCSV)
OCS_SUBSCRIPTION_NAME=$(OCS_SUBSCRIPTION_NAME)
OCS_SUBSCRIPTION_PACKAGE=$(OCS_SUBSCRIPTION_PACKAGE)
OCS_SUBSCRIPTION_CHANNEL=$(OCS_SUBSCRIPTION_CHANNEL)
OCS_SUBSCRIPTION_STARTINGCSV=$(OCS_SUBSCRIPTION_STARTINGCSV)
OCS_SUBSCRIPTION_CATALOGSOURCE=$(OCS_SUBSCRIPTION_CATALOGSOURCE)
OCS_SUBSCRIPTION_CATALOGSOURCE_NAMESPACE=$(OCS_SUBSCRIPTION_CATALOGSOURCE_NAMESPACE)
IBM_SUBSCRIPTION_NAME=$(IBM_SUBSCRIPTION_NAME)
IBM_SUBSCRIPTION_PACKAGE=$(IBM_SUBSCRIPTION_PACKAGE)
IBM_SUBSCRIPTION_CHANNEL=$(IBM_SUBSCRIPTION_CHANNEL)
IBM_SUBSCRIPTION_STARTINGCSV=$(IBM_SUBSCRIPTION_STARTINGCSV)
IBM_SUBSCRIPTION_CATALOGSOURCE=$(IBM_SUBSCRIPTION_CATALOGSOURCE)
IBM_SUBSCRIPTION_CATALOGSOURCE_NAMESPACE=$(IBM_SUBSCRIPTION_CATALOGSOURCE_NAMESPACE)
IBM_CSI_SUBSCRIPTION_STARTINGCSV=$(IBM_CSI_SUBSCRIPTION_STARTINGCSV)
endef
export MANAGER_ENV_VARS

update-mgr-env: ## Feed env variables to the manager configmap
	@echo "$$MANAGER_ENV_VARS" > config/manager/manager.env

##@ Build

build: generate fmt vet go-build ## Build manager binary.

go-build: ## Run go build against code.
	@GOBIN=${GOBIN} ./hack/go-build.sh

run: manifests generate fmt vet ## Run a controller from your host.
	go run ./main.go

docker-build: vendor-update ## Build docker image with the manager.
	docker build -t ${IMG} .

docker-push: ## Push docker image with the manager.
	docker push ${IMG}

##@ Deployment

install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl delete -f -

deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	cd config/default && $(KUSTOMIZE) edit set image rbac-proxy=$(RBAC_PROXY_IMG)
	cd config/console && $(KUSTOMIZE) edit set image odf-console=$(ODF_CONSOLE_IMG)
	$(KUSTOMIZE) build config/default | kubectl apply -f -

undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/default | kubectl delete -f -

deploy-with-olm: kustomize ## Deploy controller to the K8s cluster via OLM
	cd config/install && $(KUSTOMIZE) edit set image catalog-img=${CATALOG_IMG}
	$(KUSTOMIZE) build config/install | sed "s/odf-operator.v.*/odf-operator.v${VERSION}/g" | kubectl create -f -

undeploy-with-olm: ## Undeploy controller from the K8s cluster
	$(KUSTOMIZE) build config/install | kubectl delete -f -

.PHONY: bundle
bundle: manifests kustomize operator-sdk ## Generate bundle manifests and metadata, then validate generated files.
	$(OPERATOR_SDK) generate kustomize manifests -q
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	cd config/default && $(KUSTOMIZE) edit set image rbac-proxy=$(RBAC_PROXY_IMG)
	cd config/console && $(KUSTOMIZE) edit set image odf-console=$(ODF_CONSOLE_IMG)
	cd config/manifests/bases && $(KUSTOMIZE) edit add annotation --force 'olm.skipRange':"$(SKIP_RANGE)" && \
		$(KUSTOMIZE) edit add patch --name odf-operator.v0.0.0 --kind ClusterServiceVersion\
		--patch '[{"op": "replace", "path": "/spec/replaces", "value": "$(REPLACES)"}]'
	$(KUSTOMIZE) build config/manifests | $(OPERATOR_SDK) generate bundle -q --overwrite --version $(VERSION) $(BUNDLE_METADATA_OPTS)
	$(OPERATOR_SDK) bundle validate ./bundle

.PHONY: bundle-build
bundle-build: bundle ## Build the bundle image.
	docker build -f bundle.Dockerfile -t $(BUNDLE_IMG) .

.PHONY: bundle-push
bundle-push: ## Push the bundle image.
	$(MAKE) docker-push IMG=$(BUNDLE_IMG)

# Build a catalog image by adding bundle images to an empty catalog using the operator package manager tool, 'opm'.
# This recipe invokes 'opm' in 'semver' bundle add mode. For more information on add modes, see:
# https://github.com/operator-framework/community-operators/blob/7f1438c/docs/packaging-operator.md#updating-your-existing-operator
.PHONY: catalog-build
catalog-build: opm ## Build a catalog image.
	$(OPM) index add --container-tool docker --mode semver --tag $(CATALOG_IMG) --bundles $(BUNDLE_IMGS) $(FROM_INDEX_OPT)

# Push the catalog image.
.PHONY: catalog-push
catalog-push: ## Push a catalog image.
	$(MAKE) docker-push IMG=$(CATALOG_IMG)
