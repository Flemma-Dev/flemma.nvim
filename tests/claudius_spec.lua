
describe('Claudius setup', function()
  it('can be required without errors', function()
    local ok, claudius = pcall(require, 'claudius')
    assert.is_true(ok, 'Failed to require claudius')
    assert.is_table(claudius, 'claudius is not a table')
  end)
end)
