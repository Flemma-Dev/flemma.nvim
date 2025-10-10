--- Frontmatter initialization - registers built-in parsers
local parsers_registry = require("flemma.frontmatter.parsers")

-- Register built-in parsers
parsers_registry.register("lua", require("flemma.frontmatter.parsers.lua").parse)
parsers_registry.register("json", require("flemma.frontmatter.parsers.json").parse)

-- Side-effect only module - no exports needed
return true
