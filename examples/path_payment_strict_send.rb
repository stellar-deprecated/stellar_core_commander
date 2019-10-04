account :usd_gateway
account :eur_gateway
account :scott
account :bartek
account :andrew

create_account :usd_gateway, :master
create_account :eur_gateway, :master
create_account :scott, :master
create_account :bartek, :master
create_account :andrew, :master

close_ledger

trust :scott,  :usd_gateway, "USD"
trust :bartek, :eur_gateway, "EUR"
trust :andrew, :usd_gateway, "USD"
trust :andrew, :eur_gateway, "EUR"

close_ledger

payment :usd_gateway, :scott,  ["USD", :usd_gateway, 1000]
payment :usd_gateway, :andrew, ["USD", :usd_gateway, 200]
payment :eur_gateway, :andrew, ["EUR", :eur_gateway, 200]
payment :eur_gateway, :bartek, ["EUR", :eur_gateway, 1000]

close_ledger

offer :andrew, {buy:["USD", :usd_gateway], with:["EUR", :eur_gateway]}, 200, 1.0

close_ledger

path_payment_strict_send :scott, :bartek, ["EUR", :eur_gateway, 10], with: ["USD", :usd_gateway, 10], path: []
