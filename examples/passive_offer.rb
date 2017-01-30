use_manual_close #use_manual_close causes scc to run a process with MANUAL_CLOSE=true

account :usd_gateway
account :eur_gateway
account :scott

create_account :usd_gateway
create_account :eur_gateway
create_account :scott

close_ledger

trust :scott,  :usd_gateway, "USD"
trust :scott,  :eur_gateway, "EUR"

close_ledger

payment :usd_gateway, :scott, ["USD", :usd_gateway, 1000]
payment :eur_gateway, :scott, ["EUR", :eur_gateway, 1000]

close_ledger

passive_offer :scott, {sell:["USD", :usd_gateway], for:["EUR", :eur_gateway]}, 500, 1.0
passive_offer :scott, {buy:["USD", :usd_gateway], with:["EUR", :eur_gateway]}, 500, 1.0
