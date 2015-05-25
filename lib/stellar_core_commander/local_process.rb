module StellarCoreCommander

  class LocalProcess < Process
    include Contracts

    attr_reader :working_dir
    attr_reader :base_port
    attr_reader :identity
    attr_reader :pid
    attr_reader :wait

    def initialize(working_dir, base_port, identity)
      @working_dir = working_dir
      @base_port   = base_port
      @identity    = identity

      @server = Faraday.new(url: "http://127.0.0.1:#{http_port}") do |conn|
        conn.request :url_encoded
        conn.adapter Faraday.default_adapter
      end
    end

    Contract None => Any
    def forcescp
      run_cmd "./stellar-core", ["--forcescp"]
      raise "Could not set --forcescp" unless $?.success?
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
      raise "already running!" if running?

      forcescp
      launch_stellar_core
    end


    Contract None => Any
    def wait_for_ready
      loop do

        response = @server.get("/info") rescue false

        if response
          body = ActiveSupport::JSON.decode(response.body)

          break if body["info"]["state"] == "Synced!"
        end

        $stderr.puts "waiting until stellar-core is synced"
        sleep 1
      end
    end

    Contract None => Bool
    def running?
      return false unless @pid
      ::Process.kill 0, @pid
      true
    rescue Errno::ESRCH
      false
    end

    Contract Bool => Bool
    def shutdown(graceful=true)
      return true if !running?

      if graceful
        ::Process.kill "INT", @pid
      else
        ::Process.kill "KILL", @pid
      end

      @wait.value.success?
    end

    Contract None => Bool
    def close_ledger
      prev_ledger = latest_ledger
      next_ledger = prev_ledger + 1

      @server.get("manualclose")

      Timeout.timeout(5.0) do 
        loop do
          current_ledger = latest_ledger

          case
          when current_ledger == next_ledger
            break
          when current_ledger > next_ledger
            raise "whoa! we jumped two ledgers, from #{prev_ledger} to #{current_ledger}"
          else
            $stderr.puts "waiting for ledger #{next_ledger}"
            sleep 0.5
          end
        end
      end

      true
    end

    Contract String => Any
    def submit_transaction(envelope_hex)
      response = @server.get("tx", blob: envelope_hex)
      body = ActiveSupport::JSON.decode(response.body)

      if body["status"] == "ERROR"
        raise "transaction failed: #{body.inspect}"
      end

    end


    Contract Stellar::KeyPair => Num
    def sequence_for(account)
      row = database[:accounts].where(:accountid => account.address).first
      row[:seqnum]
    end


    Contract None => Num
    def latest_ledger
      database[:ledgerheaders].max(:ledgerseq)
    end

    Contract String => String
    def transaction_result(hex_hash)
      row = database[:txhistory].where(txid:hex_hash).first
      row[:txresult]
    end

    Contract None => Any
    def cleanup
      database.disconnect
      shutdown
      drop_database
      rm_working_dir
    end

    Contract None => Any
    def dump_database
      Dir.chdir(@working_dir) do
        `pg_dump #{database_name} --clean --no-owner`
      end
    end


    Contract None => Sequel::Database
    def database
      @database ||= Sequel.postgres(database_name)
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
      args += [{
          out: "stellar-core.log", 
          err: "stellar-core.log",
        }]

      Dir.chdir @working_dir do
        system(cmd, *args)
      end
    end

    def launch_stellar_core
      Dir.chdir @working_dir do
        sin, sout, serr, wait = Open3.popen3("./stellar-core")

        # throwaway stdout, stderr (the logs will record any output)
        Thread.new{ until (line = sout.gets).nil? ; end }
        Thread.new{ until (line = serr.gets).nil? ; end }

        @wait = wait
        @pid = wait.pid
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