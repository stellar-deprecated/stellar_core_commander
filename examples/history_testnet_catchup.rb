process :node1, [:testnet1, :testnet2, :testnet3], forcescp: false, debug: true, validate: false
on :node1 do
  raise "node1 synced but failed to catch up" if ledger_num < 5
  $stderr.puts "caught up on node1: ledger #{ledger_num}"
  check_no_error_metrics
  check_no_invariant_metrics
end

process :node2, [:testnet1, :testnet2, :testnet3], forcescp: false, catchup_complete: true, debug: true, validate: false
on :node2 do
  raise "node2 synced but failed to catch up" if ledger_num < 5
  $stderr.puts "caught up on node2: ledger #{ledger_num}"
  check_no_error_metrics
  check_no_invariant_metrics
end
