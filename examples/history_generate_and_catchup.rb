process :node1, [:node1], 1, accelerate_time: true
on :node1 do
  start_load_generation 2000, 2000, 20
  retry_until_true retries: 100 do
    $stderr.puts "load generation on node1: ledger #{ledger_num}"
    ledger_num > 10
  end
end

process :node2_minimal, [:node1], 1, forcescp: false, accelerate_time: true
on :node2_minimal do
  retry_until_true retries: 100 do
    ledger_num > 15
  end
  check_equal_states [:node1]
end


process :node2_complete, [:node1], 1, forcescp: false, accelerate_time: true, catchup_complete: true
on :node2_complete do
  retry_until_true retries: 100 do
    ledger_num > 15
  end
  check_equal_states [:node1]
end
