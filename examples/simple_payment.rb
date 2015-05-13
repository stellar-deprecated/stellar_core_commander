account :scott

create_account :scott, :master

close_ledger 

payment :master, :scott, [:native, 1000_000000]
