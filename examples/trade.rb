account :usd_gateway
account :eur_gateway
account :scott
account :bartek

create_account :usd_gateway, :master, 1000 * Stellar::ONE
create_account :eur_gateway, :master, 1000 * Stellar::ONE
create_account :scott,       :master, 1000 * Stellar::ONE
create_account :bartek,      :master, 1000 * Stellar::ONE

close_ledger

trust :scott,  :usd_gateway, "USD"
trust :bartek, :usd_gateway, "USD"
trust :scott,  :eur_gateway, "EUR"
trust :bartek, :eur_gateway, "EUR"

close_ledger

payment :usd_gateway, :scott,  ["USD", :usd_gateway, 1000 * Stellar::ONE]
payment :eur_gateway, :bartek, ["EUR", :eur_gateway, 1000 * Stellar::ONE]

close_ledger

offer :bartek, {buy:["USD", :usd_gateway], with:["EUR", :eur_gateway]}, 1000 * Stellar::ONE, 1.0

close_ledger

offer :scott, {sell:["USD", :usd_gateway], for:["EUR", :eur_gateway]}, 500 * Stellar::ONE, 1.0

offer :scott, {sell:["USD", :usd_gateway], for: :native}, 500 * Stellar::ONE, 1.0
