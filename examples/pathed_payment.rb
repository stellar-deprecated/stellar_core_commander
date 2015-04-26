account :usd_gateway
account :eur_gateway
account :scott
account :bartek
account :andrew

payment :master, :usd_gateway, [:native, 1000_000000]
payment :master, :eur_gateway, [:native, 1000_000000]

payment :master, :scott, [:native, 1000_000000]
payment :master, :bartek, [:native, 1000_000000]
payment :master, :andrew, [:native, 1000_000000]

close_ledger

trust :scott,  :usd_gateway, "USD"
trust :bartek, :eur_gateway, "EUR"
trust :andrew, :usd_gateway, "USD"
trust :andrew, :eur_gateway, "EUR"

close_ledger

payment :usd_gateway, :scott,  ["USD", :usd_gateway, 1000_000000]
payment :usd_gateway, :andrew, ["USD", :usd_gateway, 200_000000]
payment :eur_gateway, :andrew, ["EUR", :eur_gateway, 200_000000]
payment :eur_gateway, :bartek, ["EUR", :eur_gateway, 1000_000000]

close_ledger

offer :andrew, ["USD", :usd_gateway, 200_000000], ["EUR", :eur_gateway, 400_000000]

close_ledger

payment :scott, :bartek, ["EUR", :eur_gateway, 200_000000], path: ["USD", :usd_gateway]

close_ledger
