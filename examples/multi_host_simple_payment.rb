process :node1
process :node2

account :alice
account :bob

create_account :alice, :master
create_account :bob, :master

close_ledger

puts "Running txs on node1"

on :node1 do
  create_account :bob, :master
  close_ledger
  payment :master, :bob, [:native, 1000_000000]
  close_ledger
end

payment :master, :alice, [:native, 1000_000000]

