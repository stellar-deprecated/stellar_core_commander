process :node1, [:node1], 1, accelerate_time: true
on :node1 do
  generate_load_and_await_completion 100, 100, 20
  retry_until_true retries: 100 do
    ledger_num > 10
  end
  check_database_against_ledger_buckets
end

process :node2_minimal, [:node1], 1, forcescp: false, accelerate_time: true
on :node2_minimal do
  retry_until_true retries: 100 do
    ledger_num > 15
  end
  check_database_against_ledger_buckets
  check_equal_ledger_objects [:node1]
  check_ledger_sequence_is_prefix_of :node1
end


process :node2_complete, [:node1], 1, forcescp: false, accelerate_time: true, catchup_complete: true
on :node2_complete do
  retry_until_true retries: 100 do
    ledger_num > 15
  end
  check_database_against_ledger_buckets
  check_equal_ledger_objects [:node1, :node2_minimal]
  check_ledger_sequence_is_prefix_of :node1
end
