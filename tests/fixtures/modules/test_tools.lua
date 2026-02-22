return {
  definitions = {
    {
      name = "fixture_search",
      description = "Search fixture tool",
      input_schema = {
        type = "object",
        properties = {
          query = { type = "string", description = "Search query" },
        },
        required = { "query" },
      },
      execute = function(input)
        return { success = true, output = "Found: " .. (input.query or "") }
      end,
    },
  },
}
