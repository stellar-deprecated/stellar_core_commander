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

    private
    Contract Num, Stellar::KeyPair, String => String
    def config_file(base_port, identity, dsn)
      <<-EOS.strip_heredoc
        MANUAL_CLOSE=true
        PEER_PORT=#{base_port + 1}
        RUN_STANDALONE=false
        HTTP_PORT=#{base_port}
        PUBLIC_HTTP_PORT=false
        PEER_SEED="#{identity.seed}"
        VALIDATION_SEED="#{identity.seed}"
        QUORUM_THRESHOLD=1
        QUORUM_SET=["#{identity.address}"]
        DATABASE="#{dsn}"

        COMMANDS=["ll?level=trace"]

        [HISTORY.main]
        get="cp history/main/{0} {1}"
        put="cp {0} history/main/{1}"
        mkdir="mkdir -p history/main/{0}"
      EOS
    end

  end
end