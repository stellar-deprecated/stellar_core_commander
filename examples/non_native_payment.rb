account :usd_gateway
account :scott
account :andrew

create_account :usd_gateway
create_account :scott
create_account :andrew

close_ledger

trust :scott,  :usd_gateway, "USD"
trust :andrew, :usd_gateway, "USD"

close_ledger

payment :usd_gateway, :scott,  ["USD", :usd_gateway, 1000 * Stellar::ONE]

close_ledger

payment :scott, :andrew, ["USD", :usd_gateway, 500 * Stellar::ONE]
