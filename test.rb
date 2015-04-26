require 'stellar_core_commander'
require 'pry'

bin = File.expand_path("~/src/stellar/stellar-core/bin/stellar-core")
cmd = StellarCoreCommander::Commander.new(bin)

cmd.cleanup_at_exit!
p1 = cmd.make_process


binding.pry