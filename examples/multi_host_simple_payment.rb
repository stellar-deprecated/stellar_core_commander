process :node1, [:node1, :node2, :node3], 3
process :node2, [:node1, :node2, :node3], 3
process :node3, [:node1, :node2, :node3], 3

account :alice
account :bob

puts "Running txs on node1"

on :node1 do
  create_account :alice, :master
  create_account :bob, :master
  close_ledger
  payment :master, :bob, [:native, 100 * Stellar::ONE]
  close_ledger
end

payment :master, :alice, [:native, 100 * Stellar::ONE]

on :node2 do
  check_database_against_ledger_buckets
  check_ledger_sequence_is_prefix_of :node1
  equal_ledger_objects [:node1, :node3]
end
