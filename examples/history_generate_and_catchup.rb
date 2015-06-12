process :node1, [:node1], 1, accelerate_time: true
on :node1 do
  start_load_generation 20000, 20000, 100
  while ledger_num < 10
    $stderr.puts "load generation on node1: ledger #{ledger_num}"
    sleep 1
  end
end

process :node2, [:node1], 1, forcescp: false, accelerate_time: true
on :node2 do
  raise "node2 synced but failed to catch up" if ledger_num < 5
  while ledger_num < 15
    $stderr.puts "caught up on node2: ledger #{ledger_num}"
  end
end
