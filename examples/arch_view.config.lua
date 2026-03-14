return {
  source_roots = { "src" },
  component_rules = {
    { name = "app", match = { "^src%.app$", "^src%.app%..+" }, component = "app" },
    { name = "domain", match = { "^src%.domain$", "^src%.domain%..+" }, component = "domain" },
    { name = "infra", match = { "^src%.infra$", "^src%.infra%..+" }, component = "infra" },
  },
  abstract_rules = {
    { name = "ports", match = { "^src%.domain%.ports%..+" } },
  },
  forbidden_dependency_rules = {
    {
      name = "domain_does_not_depend_on_infra",
      from = { "^src%.domain%..+" },
      to = { "^src%.infra%..+" },
    },
  },
}
