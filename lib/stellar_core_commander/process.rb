module StellarCoreCommander

  class Process
    include Contracts

    attr_reader :working_dir
    attr_reader :base_port
    attr_reader :identity

    def initialize(working_dir, base_port, identity)
      @working_dir = working_dir
      @base_port   = base_port
      @identity    = identity
    end

    Contract None => Any
    def initialize_history
      run_cmd "./stellar-core", ["--newhist", "main"]
      raise "Could not initialize history" unless $?.success?
    end

    Contract None => Any
    def initialize_database
      run_cmd "./stellar-core", ["--newdb"]
      raise "Could not initialize db" unless $?.success?
    end

    Contract None => Any
    def create_database
      run_cmd "createdb", [database_name]
      raise "Could not create db: #{database_name}" unless $?.success?
    end

    Contract None => Any
    def drop_database
      run_cmd "dropdb", [database_name]
      raise "Could not drop db: #{database_name}" unless $?.success?
    end

    Contract None => Any
    def write_config
      IO.write("#{@working_dir}/stellar-core.cfg", config)
    end

    Contract None => Any
    def rm_working_dir
      FileUtils.rm_rf @working_dir
    end

    Contract None => Any
    def setup
      write_config
      create_database
      initialize_history
      initialize_database
    end

    Contract None => Num
    def run
      # launch process, return pid
    end

    Contract None => Bool
    def running?
      # signal the pid we have, see if it's running
    end

    Contract Bool => Bool
    def shutdown(graceful=true)
      # if graceful, send term
      # else, send KILL
    end

    Contract None => Bool
    def close_ledger
      # send manual close
    end

    Contract String => Bool
    def submit_transaction(envelope_hex)
      
    end

    Contract None => Any
    def cleanup
      drop_database
      rm_working_dir
    end

    Contract None => String
    def database_name
      "stellar_core_tmp_#{basename}"
    end

    Contract None => String
    def dsn
      "postgresql://dbname=#{database_name}"
    end

    Contract None => Num
    def http_port
      @base_port
    end

    Contract None => Num
    def peer_port
      @base_port + 1
    end

    private
    Contract None => String
    def basename
      File.basename(@working_dir)
    end

    Contract String, ArrayOf[String] => Maybe[Bool]
    def run_cmd(cmd, args)
      Dir.chdir @working_dir do
        system(cmd, *args)
      end
    end

    Contract None => String
    def config
      <<-EOS.strip_heredoc
        MANUAL_CLOSE=true
        PEER_PORT=#{peer_port}
        RUN_STANDALONE=false
        HTTP_PORT=#{http_port}
        PUBLIC_HTTP_PORT=false
        PEER_SEED="#{@identity.seed}"
        VALIDATION_SEED="#{@identity.seed}"
        QUORUM_THRESHOLD=1
        QUORUM_SET=["#{@identity.address}"]
        DATABASE="#{dsn}"

        [HISTORY.main]
        get="cp history/main/{0} {1}"
        put="cp {0} history/main/{1}"
        mkdir="mkdir -p history/main/{0}"
      EOS
    end

  end
end