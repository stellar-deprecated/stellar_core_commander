account :scott
puts "scott: #{get_account(:scott).address}"
create_via_friendbot :scott
wait

pp get_account_info(:scott).signers

add_onetime_signer :scott, "hello world", 1

wait

pp get_account_info(:scott).signers
