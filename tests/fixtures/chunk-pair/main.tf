# Test fixture: the policy chunker run on a synthetic list, the same list with
# one action added, and the same list in reverse order. A test compares the
# three outputs, which a single module run cannot do.

locals {
  base = [for i in range(300) : "synthetic${i % 30}:ListSomethingWithAVeryLongName${i}"]
}

module "base" {
  source  = "../../../modules/policy"
  actions = local.base
}

module "plus_one" {
  source  = "../../../modules/policy"
  actions = concat(local.base, ["synthetic7:ListOneMoreThing"])
}

module "reversed" {
  source  = "../../../modules/policy"
  actions = reverse(local.base)
}

output "base" {
  value = module.base.documents
}

output "plus_one" {
  value = module.plus_one.documents
}

output "reversed" {
  value = module.reversed.documents
}
