require 'fileutils'
module StellarCoreCommander
  class Commander
    include Contracts

    # 
    # Creates a new core commander
    # 
    Contract String => Any
    def initialize()
      @processes = []
    end

    Contract String, Hash => Process
    def make_process(type, opts = {})
      tmpdir = Dir.mktmpdir("scc")

      identity      = Stellar::KeyPair.random
      base_port     = 39132 + @processes.map(&:required_ports).sum

      process_class = case type
                        when 'local'
                          LocalProcess
                        when 'docker'
                          DockerProcess
                        else
                          raise "Unknown process type: #{type}"
                      end

      process_class.new(tmpdir, base_port, identity, opts).tap do |p|
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