process :node1, [:node1, :node2, :node3], await_sync: false
process :node2, [:node1, :node2, :node3], await_sync: false
process :node3, [:node1, :node2, :node3]

on :node1 do
  generate_load_and_await_completion 1000, 1000, 30
end

on :node2 do
  check_integrity_against :node1
end

on :node3 do
  check_integrity_against :node1
end
