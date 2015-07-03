process :node1, [:testnet1, :testnet2, :testnet3], 2, forcescp: false
on :node1 do
  raise "node1 synced but failed to catch up" if ledger_num < 5
  $stderr.puts "caught up on node1: ledger #{ledger_num}"
end
