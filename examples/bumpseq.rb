use_manual_close

account :scott
puts "scott: #{get_account(:scott).address}"
create_account :scott
close_ledger

seq = next_sequence get_account(:scott)
puts "scott: #{seq}"

bump_sequence :scott, seq + 10

close_ledger

seq = next_sequence get_account(:scott)
puts "scott: #{seq}"