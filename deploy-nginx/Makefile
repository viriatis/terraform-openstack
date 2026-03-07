.PHONY: help init plan apply destroy fmt validate clean output

help:
	@echo "Terraform OpenStack Infrastructure"
	@echo "==================================="
	@echo "  make init       - Initialize Terraform"
	@echo "  make plan       - Plan infrastructure changes"
	@echo "  make apply      - Apply infrastructure changes"
	@echo "  make destroy    - Destroy all infrastructure"
	@echo "  make fmt        - Format Terraform files"
	@echo "  make validate   - Validate Terraform configuration"
	@echo "  make output     - Display Terraform outputs"
	@echo "  make clean      - Clean up local Terraform files"

init:
	terraform init -backend-config=backend.hcl

plan: fmt validate
	terraform plan -out=tfplan

apply:
	@test -f tfplan || (echo "Run 'make plan' first" && exit 1)
	terraform apply tfplan && rm tfplan

destroy:
	terraform destroy

fmt:
	terraform fmt -recursive

validate:
	terraform validate

output:
	terraform output

clean:
	rm -rf .terraform tfplan

.DEFAULT_GOAL := help