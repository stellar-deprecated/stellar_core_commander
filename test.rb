require 'stellar_core_commander'
bin = File.expand_path("~/src/stellar/stellar-core/bin/stellar-core")
cmd = StellarCoreCommander::Commander.new(bin)

cmd.cleanup_at_exit!

p1 = cmd.make_process
p2 = cmd.make_process

puts p1.working_dir
puts p2.working_dir