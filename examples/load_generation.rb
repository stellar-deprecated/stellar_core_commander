process :node1, [:node1, :node2, :node3], 3
process :node2, [:node1, :node2, :node3], 3
process :node3, [:node1, :node2, :node3], 3

on :node1 do
  start_load_generation 1000, 1000, 30
end

retry_until_true retries: 100 do
  on :node2 do
    m = metrics
    puts "node2: transactions applied: #{m["ledger.transaction.apply"]["count"]}"
    puts "node2: transactions per sec: #{m["ledger.transaction.apply"]["mean_rate"]}"
  end
  on :node1 do
    m = metrics
    m["loadgen.run.complete"]["count"] > 0
  end
end
