process :node1, [:node1], accelerate_time: true
on :node1 do
  generate_load_and_await_completion 100, 100, 20
  retry_until_true retries: 100 do
    ledger_num > 100
  end
  check_no_error_metrics
  check_database_against_ledger_buckets
end

process :node2_minimal, [:node1], forcescp: false, accelerate_time: true
on :node2_minimal do
  retry_until_true retries: 100 do
    ledger_num > 120
  end
  check_integrity_against :node1
end


process :node2_complete, [:node1], forcescp: false, accelerate_time: true, catchup_complete: true
on :node2_complete do
  retry_until_true retries: 100 do
    ledger_num > 120
  end
  check_integrity_against :node1
end

process :node2_recent, [:node1], forcescp: false, accelerate_time: true, catchup_recent: 30
on :node2_recent do
  retry_until_true retries: 100 do
    ledger_num > 120
  end
  check_integrity_against :node1
end
