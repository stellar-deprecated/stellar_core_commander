process :node1, [:node1, :node2, :node3], 3
process :node2, [:node1, :node2, :node3], 3
process :node3, [:node1, :node2, :node3], 3

account :alice
account :bob

puts "Running txs on node1"

on :node1 do
  create_account :alice, :master
  create_account :bob, :master
  close_ledger
  payment :master, :bob, [:native, 100 * Stellar::ONE]
  close_ledger
end

payment :master, :alice, [:native, 100 * Stellar::ONE]

on :node1 do
  retries = 10
  while retries != 0
    begin
      check_equal_states [:node2, :node3]
      break
    rescue Exception => e
      sleep 1
      $stderr.puts "Unequal states, pausing and retrying"
      retries = retries - 1
      if retries == 0
        raise e
      end
    end
  end
end
