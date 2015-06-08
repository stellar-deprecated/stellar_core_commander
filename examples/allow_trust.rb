account :usd_gateway
account :scott
account :andrew

create_account :usd_gateway
create_account :scott
create_account :andrew

close_ledger

require_trust_auth :usd_gateway

close_ledger

trust :scott,  :usd_gateway, "USD"
trust :andrew, :usd_gateway, "USD"

close_ledger

allow_trust :usd_gateway, :scott, "USD"
