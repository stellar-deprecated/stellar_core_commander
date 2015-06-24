account :scott

create_account :scott, :master

close_ledger

payment :master, :scott, [:native, 1000 * Stellar::ONE]

check_no_error_metrics
