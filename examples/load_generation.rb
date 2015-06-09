process :node1, [:node1, :node2, :node3], 2
process :node2, [:node1, :node2, :node3], 2
process :node3, [:node1, :node2, :node3], 2

on :node1 do
  start_load_generation 10000, 10000, 100
end

on :node2 do
  while true
    m = metrics
    puts "transactions applied: #{m["ledger.transaction.apply"]["count"]}"
    puts "transactions per sec: #{m["ledger.transaction.apply"]["mean_rate"]}"
    sleep 5
    if (m["loadgen.run.complete"]["count"] rescue 0) > 0
      break
    end
  end
end
