process :node1, [:node1, :node2, :node3]
process :node2, [:node1, :node2, :node3]
process :node3, [:node1, :node2, :node3]

account :alice
account :bob

puts "Running txs on node1"

on :node1 do
  create_account :alice, :master
  create_account :bob, :master
  close_ledger
  payment :master, :bob, [:native, 100]
  close_ledger
end

payment :master, :alice, [:native, 100]

on :node2 do
  check_integrity_against :node1
end

on :node3 do
  check_integrity_against :node1
end
