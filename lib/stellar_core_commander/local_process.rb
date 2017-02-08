module StellarCoreCommander

  class LocalProcess < Process
    include Contracts

    attr_reader :pid

    def initialize(params)
      raise "`host` param is unsupported on LocalProcess, please use `-p docker` for this recipe." if params[:host]
      $stderr.puts "Warning: Ignoring `atlas` param since LocalProcess doesn't support this." if params[:atlas]

      super
      @stellar_core_bin = params[:stellar_core_bin]
      @database_url     = params[:database].try(:strip)
      @cmd              = Cmd.new(working_dir)

      setup_working_dir
    end

    Contract None => Any
    def forcescp
      res = capture_output(@cmd.run_cmd "./stellar-core", ["--forcescp"])
      raise "Could not set --forcescp: " + res.stderr.to_s unless res.success
    end

    Contract None => Any
    def initialize_history
      Dir.mkdir(history_dir) unless File.exists?(history_dir)
      res = capture_output(@cmd.run_cmd "./stellar-core", ["--newhist", @name.to_s])
      raise "Could not initialize history: " + res.stderr.to_s unless res.success
    end

    Contract None => Any
    def initialize_database
      res = capture_output(@cmd.run_cmd "./stellar-core", ["--newdb"])
      raise "Could not initialize db: " + res.stderr.to_s unless res.success
    end

    Contract None => Any
    def create_database
      res = capture_output(@cmd.run_cmd "createdb", [database_name])
      raise "Could not create db: #{database_name}: " + res.stderr.to_s unless res.success
    end

    Contract None => Any
    def drop_database
      res = capture_output(@cmd.run_cmd "dropdb", [database_name])
      raise "Could not drop db: #{database_name}: " + res.stderr.to_s unless res.success
    end

    Contract None => Any
    def write_config
      IO.write("#{@working_dir}/stellar-core.cfg", config)
    end

    Contract None => String
    def history_dir
      File.expand_path("#{working_dir}/../history-archives")
    end

    Contract None => Any
    def setup
      write_config
      create_database unless @keep_database
      initialize_database
      initialize_history
    end

    Contract None => Num
    def launch_process
      forcescp if @forcescp
      launch_stellar_core
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

      @wait_value == 0
    end

    Contract None => Any
    def cleanup
      database.disconnect
      dump_database
      dump_scp_state
      dump_info
      dump_metrics
      shutdown
      drop_database unless @keep_database
    end

    Contract None => Any
    def dump_database
      fname = "#{working_dir}/database-#{Time.now.to_i}-#{rand 100000}.sql"
      $stderr.puts "dumping database to #{fname}"
      sql = `pg_dump #{database_name} --clean --if-exists --no-owner --no-acl --inserts`
      File.open(fname, 'w') {|f| f.write(sql) }
      fname
    end

    Contract None => String
    def default_database_url
      "postgres:///#{idname}"
    end

    def crash
      `kill -ABRT #{@pid}`
    end

    private
    def launch_stellar_core
      Dir.chdir @working_dir do
        @pid = ::Process.spawn("./stellar-core",
                               :out => "stdout.txt",
                               :err => "stderr.txt")
        @wait = Thread.new {
          @wait_value = ::Process.wait(@pid);
          $stderr.puts "stellar-core process exited: #{@wait_value}"
        }
      end
      @pid
    end

    Contract None => String
    def config
      <<-EOS.strip_heredoc
        PEER_PORT=#{peer_port}
        RUN_STANDALONE=false
        HTTP_PORT=#{http_port}
        PUBLIC_HTTP_PORT=false
        NODE_SEED="#{@identity.seed}"
        #{"NODE_IS_VALIDATOR=true" if @validate}

        ARTIFICIALLY_GENERATE_LOAD_FOR_TESTING=true
        DESIRED_MAX_TX_PER_LEDGER=10000
        #{"ARTIFICIALLY_ACCELERATE_TIME_FOR_TESTING=true" if @accelerate_time}
        #{"CATCHUP_COMPLETE=true" if @catchup_complete}
        #{"CATCHUP_RECENT=" + @catchup_recent.to_s if @catchup_recent}

        DATABASE="#{dsn}"
        PREFERRED_PEERS=#{peer_connections}

        #{"MANUAL_CLOSE=true" if manual_close?}
        #{"COMMANDS=[\"ll?level=debug\"]" if @debug}

        FAILURE_SAFETY=0
        UNSAFE_QUORUM=true

        NETWORK_PASSPHRASE="#{network_passphrase}"

        [QUORUM_SET]
        VALIDATORS=#{quorum}

        #{history_sources}
      EOS
    end

    Contract Symbol => String
    def one_history_source(n)
      dir = "#{history_dir}/#{n}"
      if n == @name
        <<-EOS.strip_heredoc
          [HISTORY.#{n}]
          get="cp #{dir}/{0} {1}"
          put="cp {0} #{dir}/{1}"
          mkdir="mkdir -p #{dir}/{0}"
        EOS
      else
        name = n.to_s
        get = "cp #{history_dir}/%s/{0} {1}"
        if SPECIAL_PEERS.has_key? n
          name = SPECIAL_PEERS[n][:name]
          get = SPECIAL_PEERS[n][:get]
        end
        get.sub!('%s', name)
        <<-EOS.strip_heredoc
          [HISTORY.#{name}]
          get="#{get}"
        EOS
      end
    end

    Contract None => String
    def history_sources
      @quorum.map {|n| one_history_source n}.join("\n")
    end

    def setup_working_dir
      if @stellar_core_bin.blank?
        search = `which stellar-core`.strip

        if $?.success?
          @stellar_core_bin = search
        else
          $stderr.puts "Could not find a `stellar-core` binary, please use --stellar-core-bin to specify"
          exit 1
        end
      end

      FileUtils.cp(@stellar_core_bin, "#{working_dir}/stellar-core")
    end

  end
end
