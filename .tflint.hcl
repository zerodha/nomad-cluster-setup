config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.50.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# nomad-clients still declares an unused `vpc` input. Removing it would break
# callers, so this stays off until the next major release drops it.
rule "terraform_unused_declarations" {
  enabled = false
}
