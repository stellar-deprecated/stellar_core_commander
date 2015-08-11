old_image = ENV["OLD_IMAGE"]
new_image = ENV["NEW_IMAGE"]

raise "missing ENV['OLD_IMAGE']" unless old_image
raise "missing ENV['NEW_IMAGE']" unless new_image

peers = [:oldnode1, :oldnode2, :newnode1, :newnode2]

process :oldnode1, peers, docker_core_image: old_image, docker_pull: true
process :oldnode2, peers, docker_core_image: old_image, docker_pull: true
process :newnode1, peers, docker_core_image: new_image, docker_pull: true
process :newnode2, peers, docker_core_image: new_image, docker_pull: true

account :alice
account :bob

on :oldnode2 do
  create_account :alice, :master
  create_account :bob, :master
  while not ((account_created :bob) and (account_created :alice))
    $stderr.puts "Awaiting account-creation"
    close_ledger
  end
  $stderr.puts "oldnode2 bob balance: #{(balance :bob)}"
  $stderr.puts "oldnode2 alice balance: #{(balance :alice)}"
  payment :master, :bob, [:native, 100 * Stellar::ONE]
  close_ledger
end

on :newnode1 do
  $stderr.puts "newnode1 bob balance: #{(balance :bob)}"
  $stderr.puts "newnode1 alice balance: #{(balance :alice)}"
  raise if (balance :bob) != 1100 * Stellar::ONE
  payment :master, :alice, [:native, 100 * Stellar::ONE]
  close_ledger
  check_integrity_against :oldnode1
  check_integrity_against :oldnode2
end

on :oldnode1 do
  $stderr.puts "oldnode1 bob balance: #{(balance :bob)}"
  $stderr.puts "oldnode1 alice balance: #{(balance :alice)}"
  raise if (balance :alice) != 1100 * Stellar::ONE
  check_integrity_against :newnode1
  check_integrity_against :newnode2
end
