process :node1, [:node1, :node2, :node3], host: '192.168.99.105', await_sync: false
process :node2, [:node1, :node2, :node3], host: '192.168.99.104', await_sync: false
process :node3, [:node1, :node2, :node3], host: '192.168.99.103'

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

