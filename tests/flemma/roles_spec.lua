local roles = require("flemma.utilities.roles")

describe("flemma.utilities.roles", function()
  describe("constants", function()
    it("exposes buffer-format role names", function()
      assert.equals("You", roles.YOU)
      assert.equals("Assistant", roles.ASSISTANT)
      assert.equals("System", roles.SYSTEM)
    end)
  end)

  describe("to_key()", function()
    it("maps 'You' to 'user'", function()
      assert.equals("user", roles.to_key("You"))
    end)

    it("maps 'Assistant' to 'assistant'", function()
      assert.equals("assistant", roles.to_key("Assistant"))
    end)

    it("maps 'System' to 'system'", function()
      assert.equals("system", roles.to_key("System"))
    end)

    it("lowercases unknown roles as fallback", function()
      assert.equals("custom", roles.to_key("Custom"))
    end)
  end)

  describe("is_user()", function()
    it("returns true for 'You'", function()
      assert.is_true(roles.is_user("You"))
    end)

    it("returns false for 'Assistant'", function()
      assert.is_false(roles.is_user("Assistant"))
    end)

    it("returns false for 'System'", function()
      assert.is_false(roles.is_user("System"))
    end)
  end)

  describe("capitalize()", function()
    it("capitalizes 'user' to 'User'", function()
      assert.equals("User", roles.capitalize("user"))
    end)

    it("capitalizes 'assistant' to 'Assistant'", function()
      assert.equals("Assistant", roles.capitalize("assistant"))
    end)

    it("capitalizes single character", function()
      assert.equals("A", roles.capitalize("a"))
    end)
  end)

  describe("highlight_group()", function()
    it("builds FlemmaRoleUser from prefix and 'You'", function()
      assert.equals("FlemmaRoleUser", roles.highlight_group("FlemmaRole", "You"))
    end)

    it("builds FlemmaLineAssistant from prefix and 'Assistant'", function()
      assert.equals("FlemmaLineAssistant", roles.highlight_group("FlemmaLine", "Assistant"))
    end)

    it("builds FlemmaRulerSystem from prefix and 'System'", function()
      assert.equals("FlemmaRulerSystem", roles.highlight_group("FlemmaRuler", "System"))
    end)

    it("builds FlemmaUser from 'Flemma' prefix and 'You'", function()
      assert.equals("FlemmaUser", roles.highlight_group("Flemma", "You"))
    end)
  end)
end)
