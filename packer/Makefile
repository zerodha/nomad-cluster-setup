DRY_RUN := true

.PHONY: build
build:
	PKR_VAR_dry_run=${DRY_RUN} PKR_VAR_install_docker=true \
	packer build ./ami.pkr.hcl

.PHONY: build-no-docker
build-no-docker:
	PKR_VAR_dry_run=${DRY_RUN} PKR_VAR_install_docker=false \
	packer build ./ami.pkr.hcl
