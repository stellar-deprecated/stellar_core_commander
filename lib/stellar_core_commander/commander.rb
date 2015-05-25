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

    Contract String => Process
    def make_process(type)
      tmpdir = Dir.mktmpdir("scc")

      identity      = Stellar::KeyPair.random
      base_port     = 39132 + (@processes.length * 3)

      if type == 'local'
        FileUtils.cp(@stellar_core_bin, "#{tmpdir}/stellar-core")
        process = LocalProcess.new(tmpdir, base_port, identity)
      elsif type == 'docker'
        process = DockerProcess.new(tmpdir, base_port, identity)
      else
        raise "Unknown process type: #{type}"
      end

      process.tap do |p|
        p.setup
        @processes << p
      end
    end

    def cleanup
      @processes.each(&:cleanup)
    end

    def cleanup_at_exit!
      at_exit do
        $stderr.puts "cleaning up #{@processes.length} processes"
        cleanup
      end
    end

  end
end