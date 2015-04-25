require 'fileutils'
module StellarCoreCommander
  class Commander
    include Contracts

    # 
    # Creates a new core commander
    # 
    Contract String => Any
    def initialize(stellar_core_bin)
      @stellar_core_bin = stellar_core_bin
      raise "no file at #{stellar_core_bin}" unless File.exist?(stellar_core_bin)

      @processes = []
    end

    Contract None => Process
    def make_process
      tmpdir        = Dir.mktmpdir
      identity      = Stellar::KeyPair.random
      base_port     = 39132

      FileUtils.cp(@stellar_core_bin, "#{tmpdir}/stellar-core")
      Process.new(tmpdir, base_port, identity).tap do |p|
        p.setup
        @processes << p
      end
    end

    def cleanup
      @processes.each(&:cleanup)
    end

    def cleanup_at_exit!
      at_exit do
        puts "cleaning up #{@processes.length} processes"
        cleanup
      end
    end

  end
end