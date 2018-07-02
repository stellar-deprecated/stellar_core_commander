require 'set'
require 'socket'
require 'timeout'
require 'csv'

module StellarCoreCommander

  class UnexpectedDifference < StandardError
    def initialize(kind, x, y)
      @kind = kind
      @x = x
      @y = y
    end
    def message
      "Unexpected difference in #{@kind}: #{@x} != #{@y}"
    end
  end

  class Process
    include Contracts

    class Crash < StandardError ; end
    class AlreadyRunning < StandardError ; end

    attr_reader :transactor
    attr_reader :working_dir
    attr_reader :name
    attr_reader :base_port
    attr_reader :identity
    attr_reader :server
    attr_accessor :unverified
    attr_reader :host
    attr_reader :atlas
    attr_reader :atlas_interval
    attr_reader :network_passphrase

    DEFAULT_HOST = '127.0.0.1'

    SPECIAL_PEERS = {
      :testnet1 => {
        :dns => "core-testnet1.stellar.org",
        :key => "GDKXE2OZMJIPOSLNA6N6F2BVCI3O777I2OOC4BV7VOYUEHYX7RTRYA7Y",
        :name => "core_testnet_001",
        :get => "wget -q https://s3-eu-west-1.amazonaws.com/history.stellar.org/prd/core-testnet/%s/{0} -O {1}"
      },
      :testnet2 => {
        :dns => "core-testnet2.stellar.org",
        :key => "GCUCJTIYXSOXKBSNFGNFWW5MUQ54HKRPGJUTQFJ5RQXZXNOLNXYDHRAP",
        :name => "core_testnet_002",
        :get => "wget -q https://s3-eu-west-1.amazonaws.com/history.stellar.org/prd/core-testnet/%s/{0} -O {1}"
      },
      :testnet3 => {
        :dns => "core-testnet3.stellar.org",
        :key => "GC2V2EFSXN6SQTWVYA5EPJPBWWIMSD2XQNKUOHGEKB535AQE2I6IXV2Z",
        :name => "core_testnet_003",
        :get => "wget -q https://s3-eu-west-1.amazonaws.com/history.stellar.org/prd/core-testnet/%s/{0} -O {1}"
      },
      :pubnet1 => {
        :dns => "core-live4.stellar.org",
        :key => "GCGB2S2KGYARPVIA37HYZXVRM2YZUEXA6S33ZU5BUDC6THSB62LZSTYH",
        :name => "core_live_001",
        :get => "curl -sf http://history.stellar.org/prd/core-live/%s/{0} -o {1}"
      },
      :pubnet2 => {
        :dns => "core-live5.stellar.org",
        :key => "GCM6QMP3DLRPTAZW2UZPCPX2LF3SXWXKPMP3GKFZBDSF3QZGV2G5QSTK",
        :name => "core_live_002",
        :get => "curl -sf http://history.stellar.org/prd/core-live/%s/{0} -o {1}"
      },
      :pubnet3 => {
        :dns => "core-live6.stellar.org",
        :key => "GABMKJM6I25XI4K7U6XWMULOUQIQ27BCTMLS6BYYSOWKTBUXVRJSXHYQ",
        :name => "core_live_003",
        :get => "curl -sf http://history.stellar.org/prd/core-live/%s/{0} -o {1}"
      }
    }

    Contract({
      transactor:          Transactor,
      working_dir:         String,
      name:                Symbol,
      base_port:           Num,
      identity:            Stellar::KeyPair,
      quorum:              ArrayOf[Symbol],
      peers:               Maybe[ArrayOf[Symbol]],
      manual_close:        Maybe[Bool],
      await_sync:          Maybe[Bool],
      accelerate_time:     Maybe[Bool],
      catchup_complete:    Maybe[Bool],
      catchup_recent:      Maybe[Num],
      forcescp:            Maybe[Bool],
      validate:            Maybe[Bool],
      host:                Maybe[String],
      atlas:               Maybe[String],
      atlas_interval:      Num,
      use_s3:              Bool,
      s3_history_prefix:   String,
      s3_history_region:   String,
      database_url:        Maybe[String],
      keep_database:       Maybe[Bool],
      debug:               Maybe[Bool],
      wait_timeout:        Maybe[Num],
      network_passphrase:  Maybe[String],
      protocol_version:    Maybe[Or[Num, String]],
    } => Any)
    def initialize(params)
      #config
      @transactor         = params[:transactor]
      @working_dir        = params[:working_dir]
      @cmd                = Cmd.new(@working_dir)
      @name               = params[:name]
      @base_port          = params[:base_port]
      @identity           = params[:identity]
      @quorum             = params[:quorum]
      @peers              = params[:peers] || params[:quorum]
      @manual_close       = params[:manual_close] || false
      @await_sync         = @manual_close ? false : params.fetch(:await_sync, true)
      @accelerate_time    = params[:accelerate_time] || false
      @catchup_complete   = params[:catchup_complete] || false
      @catchup_recent     = params[:catchup_recent] || false
      @forcescp           = params.fetch(:forcescp, true)
      @validate           = params.fetch(:validate, true)
      @host               = params[:host]
      @atlas              = params[:atlas]
      @atlas_interval     = params[:atlas_interval]
      @use_s3             = params[:use_s3]
      @s3_history_region  = params[:s3_history_region]
      @s3_history_prefix  = params[:s3_history_prefix]
      @database_url       = params[:database_url]
      @keep_database      = params[:keep_database]
      @debug              = params[:debug]
      @wait_timeout       = params[:wait_timeout] || 10
      @network_passphrase = params[:network_passphrase] || Stellar::Networks::TESTNET
      @protocol_version   = params[:protocol_version] || "latest"

      # state
      @unverified   = []
      @sequences    = Hash.new {|hash, account| hash[account] = (account_row account)[:seqnum]}
      @is_setup     = false

      if not @quorum.include? @name
        @quorum = @quorum + [@name]
      end

      if not @peers.include? @name
        @peers = @peers + [@name]
      end

      @server = Faraday.new(url: "http://#{hostname}:#{http_port}") do |conn|
        conn.request :url_encoded
        conn.adapter Faraday.default_adapter
      end
    end

    Contract None => Bool
    def has_special_peers?
      @peers.any? {|q| SPECIAL_PEERS.has_key? q}
    end

    Contract ArrayOf[Symbol], Symbol, Bool, Proc => ArrayOf[String]
    def node_map_or_special_field(nodes, field, include_self)
      specials = nodes.select {|q| SPECIAL_PEERS.has_key? q}
      if specials.empty?
        (nodes.map do |q|
          if q != @name or include_self
            yield q
          end
        end).compact
      else
        specials.map {|q| SPECIAL_PEERS[q][field]}
      end
    end

    Contract None => ArrayOf[String]
    def quorum
      node_map_or_special_field @quorum, :key, @validate do |q|
        @transactor.get_process(q).identity.address
      end
    end

    Contract None => ArrayOf[String]
    def peer_names
      node_map_or_special_field @peers, :name, true do |q|
        q.to_s
      end
    end

    Contract None => ArrayOf[String]
    def peer_connections
      node_map_or_special_field @peers, :dns, false do |q|
        p = @transactor.get_process(q)
        "#{p.hostname}:#{p.peer_port}"
      end
    end

    Contract None => Num
    def required_ports
      2
    end

    Contract None => String
    def idname
      "#{@name}-#{@base_port}-#{@identity.address[0..5]}"
    end

    Contract None => String
    def database_url
      if @database_url.present?
        @database_url.strip
      else
        default_database_url
      end
    end

    Contract None => URI::Generic
    def database_uri
      URI.parse(database_url)
    end

    Contract None => Maybe[String]
    def database_host
      database_uri.host
    end

    Contract None => String
    def database_name
      database_uri.path[1..-1]
    end

    Contract None => Sequel::Database
    def database
      @database ||= Sequel.connect(database_url)
    end

    Contract None => Maybe[String]
    def database_user
      database_uri.user
    end

    Contract None => Maybe[String]
    def database_password
      database_uri.password
    end

    Contract None => String
    def database_port
      database_uri.port || "5432"
    end

    Contract None => String
    def dsn
      base = "postgresql://dbname=#{database_name} "
      base << " user=#{database_user}" if database_user.present?
      base << " password=#{database_password}" if database_password.present?
      base << " host=#{database_host} port=#{database_port}" if database_host.present?

      base
    end

    Contract None => Any
    def wait_for_ready
      Timeout.timeout(sync_timeout) do
        loop do
          break if synced? || (!await_sync? && !booting?)
          raise Process::Crash, "process #{name} has crashed while waiting for being #{await_sync? ? 'synced' : 'ready'}" if crashed?
          $stderr.puts "waiting until stellar-core #{idname} is #{await_sync? ? 'synced' : 'ready'} (state: #{info_field 'state'}, SCP quorum: #{scp_quorum_num}, Status: #{info_status})"
          sleep 1
        end
      end
      $stderr.puts "Wait is over! stellar-core #{idname} is #{await_sync? ? 'synced' : 'ready'} (state: #{info_field 'state'}, SCP quorum: #{scp_quorum_num}, Status: #{info_status})"
    end

    Contract None => Bool
    def manual_close?
      @manual_close
    end

    Contract None => Bool
    def close_ledger
      prev_ledger = latest_ledger
      next_ledger = prev_ledger + 1

      Timeout.timeout(close_timeout) do

        server.get("manualclose") if manual_close?

        loop do
          raise Process::Crash, "process #{name} has crashed while waiting for ledger close" if crashed?
          current_ledger = latest_ledger

          case
          when current_ledger >= next_ledger
            break
          else
            $stderr.puts "#{idname} waiting for ledger #{next_ledger} (current: #{current_ledger}, SCP quorum: #{scp_quorum_num}, Status: #{info_status})"
            sleep 0.5
          end
        end
      end
      @sequences.clear
      $stderr.puts "#{idname} closed #{latest_ledger}"

      true
    end

    Contract Or[Num, String] => Any
    def set_upgrades(protocolversion="latest")

      if protocolversion == "latest"
        version = info.fetch("protocol_version", -1)
      else
        version = protocolversion
      end
      raise "Unable to retrieve protocol version. Try again later or pass version manually." if version == -1

      response = server.get("/upgrades?mode=set&upgradetime=1970-01-01T00:00:00Z&maxtxsize=10000&protocolversion=#{version}")
      response = response.body.downcase
      if response.include? "exception"
        $stderr.puts "Did not submit upgrades: #{response}"
      end
    end

    Contract Num, Symbol => Any
    def catchup(ledger, mode)
      server.get("/catchup?ledger=#{ledger}&mode=#{mode}")
    end

    Contract None => Hash
    def info
      info!
    rescue
      {}
    end

    def info!
      response = server.get("/info")
      body = ActiveSupport::JSON.decode(response.body)
      body["info"]
    end

    Contract String => Any
    def info_field(k)
      i = info
      i[k]
    rescue
      false
    end

    Contract None => Bool
    def synced?
      (info_field "state") == "Synced!"
    end

    Contract None => Bool
    def booting?
      s = (info_field "state")
      return !s || s == "Booting"
    end

    Contract None => Num
    def ledger_num
      (info_field "ledger")["num"]
    rescue
      0
    end

    Contract None => Any
    def scp_quorum_info
      (info_field "quorum")
    rescue
      false
    end

    Contract None => String
    def info_status
      s = info_field "status"
      v = "#{s}"
      return v == "" ? "[]" : v
    rescue
      "[]"
    end

    Contract None => Num
    def scp_quorum_num
      q = scp_quorum_info
      q.keys[0].to_i
    rescue
      2
    end

    Contract None => Bool
    def await_sync?
      @await_sync
    end

    Contract None => Hash
    def metrics
      response = server.get("/metrics")
      body = ActiveSupport::JSON.decode(response.body)
      body["metrics"]
    rescue
      {}
    end

    Contract None => Any
    def clear_metrics
      server.get("/clearmetrics")
    rescue
      nil
    end

    Contract String => Num
    def metrics_count(k)
      m = metrics
      m[k]["count"]
    rescue
      0
    end

    Contract String => Num
    def metrics_1m_rate(k)
      m = metrics
      m[k]["1_min_rate"]
    rescue
      0
    end

    Contract String => Any
    def dump_server_query(s)
      fname = "#{working_dir}/#{s}-#{Time.now.to_i}-#{rand 100000}.json"
      $stderr.puts "dumping server query #{fname}"
      response = server.get("/#{s}")
      File.open(fname, 'w') {|f| f.write(response.body) }
    rescue
      nil
    end

    Contract None => Any
    def dump_metrics
      dump_server_query("metrics")
    end

    METRICS_HEADER = [
    'Time',
    'Type',
    'Accounts',
    'Expected Txs',
    'Applied Txs',
    'Tx Rate',
    'Batchsize',
    'Txs/Ledger Mean',
    'Txs/Ledger StdDev',
    'Load Step Rate',
    'Load Step Mean',
    'Nominate Mean',
    'Nominate Min',
    'Nominate Max',
    'Nominate StdDev',
    'Nominate Median',
    'Nominate 75th',
    'Nominate 95th',
    'Nominate 99th',
    'Prepare Mean',
    'Prepare Min',
    'Prepare Max',
    'Prepare StdDev',
    'Prepare Median',
    'Prepare 75th',
    'Prepare 95th',
    'Prepare 99th',
    'Close Mean',
    'Close Min',
    'Close Max',
    'Close StdDev',
    'Close Median',
    'Close 75th',
    'Close 95th',
    'Close 99th',
    'Close Rate',
    ]

    Contract String, Symbol, Num, Num, Or[Symbol, Num], Num => Any
    def record_performance_metrics(fname, txtype, accounts, txs, txrate, batchsize)
      m = metrics
      fname = "#{working_dir}/#{fname}"
      timestamp = Time.now.strftime('%Y-%m-%d_%H:%M:%S.%L')

      run_data = [timestamp, txtype, accounts, txs, transactions_applied, txrate, batchsize]
      run_data.push(m["ledger.transaction.count"]["mean"])
      run_data.push(m["ledger.transaction.count"]["stddev"])

      if m.key?("loadgen.step.submit")
        run_data.push(m["loadgen.step.submit"]["mean_rate"])
        run_data.push(m["loadgen.step.submit"]["mean"])
      else
        run_data.push("NA")
        run_data.push("NA")
      end

      metric_fields = ["scp.timing.nominated", "scp.timing.externalized", "ledger.ledger.close"]
      metric_fields.each { |field|
        run_data.push(m[field]["mean"])
        run_data.push(m[field]["min"])
        run_data.push(m[field]["max"])
        run_data.push(m[field]["stddev"])
        run_data.push(m[field]["median"])
        run_data.push(m[field]["75%"])
        run_data.push(m[field]["95%"])
        run_data.push(m[field]["99%"])
      }

      run_data.push(m["ledger.ledger.close"]["mean_rate"])

      write_csv fname, METRICS_HEADER unless File.file?(fname)
      if METRICS_HEADER.length == run_data.length
        write_csv fname, run_data
      else
        raise "#{@name}: METRICS_HEADER and run_data have different number of columns."
      end
    end

    Contract String, Array => Any
    def write_csv(fname, data)
      CSV.open(fname, 'a', {:col_sep => "\t"}) do |csv|
        csv << data
      end
    end

    Contract None => Any
    def dump_info
      dump_server_query("info")
    end

    Contract None => Any
    def dump_scp_state
      dump_server_query("scp")
    end

    Contract None => Num
    def scp_value_nominating
      metrics_count "scp.value.nominating"
    end

    Contract None => Num
    def scp_quorum_heard
      metrics_count "scp.quorum.heard"
    end

    Contract None => ArrayOf[String]
    def invariants
      ["AccountSubEntriesCountIsValid",
       "BucketListIsConsistentWithDatabase",
       "ConservationOfLumens",
       "LedgerEntryIsValid",
       "MinimumAccountBalance"]
    end

    Contract None => Bool
    def check_no_error_metrics
      m = metrics
      for metric in ["scp.envelope.invalidsig",
                     "history.publish.failure",
                     "history.catchup.failure"]
        c = m[metric]["count"] rescue 0
        if c != 0
          raise "nonzero metrics count for #{metric}: #{c}"
        end
      end

      inv_str = "invariant.does-not-hold.count"
      for inv in invariants
        c = m["#{inv_str}.#{inv}"]["count"] rescue 0
        if c != 0
          raise "Invariant #{inv} failed #{c} times"
        end
      end
      true
    end

    Contract Symbol, Num, Num, Or[Symbol, Num], Num => Any
    def start_load_generation(mode, accounts, txs, txrate, batchsize)
      server.get("/generateload?mode=#{mode}&accounts=#{accounts}&txs=#{txs}&txrate=#{txrate}&batchsize=#{batchsize}")
    end

    Contract None => Num
    def load_generation_runs
      metrics_count "loadgen.run.complete"
    end

    Contract None => Num
    def transactions_applied
      metrics_count "ledger.transaction.apply"
    end

    Contract None => Num
    def transactions_per_second
      metrics_1m_rate "ledger.transaction.apply"
    end

    Contract None => Num
    def operations_per_second
      metrics_1m_rate "transaction.op.apply"
    end

    Contract None => Num
    def http_port
      base_port
    end

    Contract None => Num
    def peer_port
      base_port + 1
    end

    Contract String => Any
    def submit_transaction(envelope_hex)
      response = server.get("tx", blob: envelope_hex)
      body = ActiveSupport::JSON.decode(response.body)

      if body["status"] == "ERROR"
        xdr = Convert.from_base64(body["error"])
        result = Stellar::TransactionResult.from_xdr(xdr)
        raise "transaction on #{idname} failed: #{result.inspect}"
      end

    end

    Contract Stellar::KeyPair => Any
    def account_row(account)
      row = database[:accounts].where(:accountid => account.address).first
      raise "Missing account in #{idname}'s database: #{account.address}" unless row
      row
    end

    Contract Stellar::KeyPair => Num
    def sequence_for(account)
      @sequences[account]
    end

    Contract Stellar::KeyPair => Num
    def balance_for(account)
      (account_row account)[:balance]
    end

    Contract None => Num
    def latest_ledger
      database[:ledgerheaders].max(:ledgerseq)
    end

    Contract String => Any
    def db_store_state(name)
      database.select(:state).from(:storestate).filter(statename: name).first[:state]
    end

    Contract None => String
    def latest_ledger_hash
      s_lcl = db_store_state("lastclosedledger")
      t_lcl = database.select(:ledgerhash)
        .from(:ledgerheaders)
        .filter(:ledgerseq=>latest_ledger).first[:ledgerhash]
      raise "inconsistent last-ledger hashes in db: #{t_lcl} vs. #{s_lcl}" if t_lcl != s_lcl
      s_lcl
    end

    Contract None => Any
    def history_archive_state
      ActiveSupport::JSON.decode(db_store_state("historyarchivestate"))
    end

    Contract None => Num
    def account_count
      database.fetch("SELECT count(*) FROM accounts").first[:count]
    end

    Contract None => Num
    def trustline_count
      database.fetch("SELECT count(*) FROM trustlines").first[:count]
    end

    Contract None => Num
    def offer_count
      database.fetch("SELECT count(*) FROM offers").first[:count]
    end

    Contract None => ArrayOf[Any]
    def ten_accounts
      database.fetch("SELECT * FROM accounts ORDER BY accountid LIMIT 10").all
    end

    Contract None => ArrayOf[Any]
    def ten_offers
      database.fetch("SELECT * FROM offers ORDER BY sellerid LIMIT 10").all
    end

    Contract None => ArrayOf[Any]
    def ten_trustlines
      database.fetch("SELECT * FROM trustlines ORDER BY accountid, issuer, assetcode LIMIT 10").all
    end

    Contract String, Any, Any => nil
    def check_equal(kind, x, y)
      raise UnexpectedDifference.new(kind, x, y) if x != y
    end

    Contract String, ArrayOf[Any], ArrayOf[Any] => nil
    def check_equal_by_column(kind, x, y)
      x.zip(y).each do |rowx, rowy|
        rowx.each do |key, val|
            raise UnexpectedDifference.new(key, x, y) if (rowy.has_key?(key) and val != rowy[key])
        end
        rowy.each do |key, val|
            raise UnexpectedDifference.new(key, x, y) if (rowx.has_key?(key) and val != rowx[key])
        end
      end
      return
    end

    Contract Process => nil
    def check_equal_ledger_objects(other)
      check_equal "account count", account_count, other.account_count
      check_equal "trustline count", trustline_count, other.trustline_count
      check_equal "offer count", offer_count, other.offer_count

      check_equal_by_column "ten accounts", ten_accounts, other.ten_accounts
      check_equal_by_column "ten trustlines", ten_trustlines, other.ten_trustlines
      check_equal_by_column "ten offers", ten_offers, other.ten_offers
    end

    Contract Process => Any
    def check_ledger_sequence_matches(other)
      q = "SELECT ledgerseq, ledgerhash FROM ledgerheaders ORDER BY ledgerseq"
      our_headers = database.fetch(q).all
      other_headers = other.database.fetch(q).all
      our_ledger_seq_numbers = our_headers.map.with_index { |x| x[:ledgerseq] }
      other_ledger_seq_numbers = other_headers.map { |x| x[:ledgerseq] }
      common_ledger_seq_numbers = our_ledger_seq_numbers.to_set & other_ledger_seq_numbers
      our_hash = {}
      our_headers.each do |row|
        if common_ledger_seq_numbers.include?(row[:ledgerseq])
            our_hash[row[:ledgerseq]] = row[:ledgerhash]
        end
      end
      other_hash = {}
      other_headers.each do |row|
        if common_ledger_seq_numbers.include?(row[:ledgerseq])
            other_hash[row[:ledgerseq]] = row[:ledgerhash]
        end
      end
      common_ledger_seq_numbers.each do |ledger_seq_numbers|
        check_equal "ledger hashes", other_hash[ledger_seq_numbers], our_hash[ledger_seq_numbers]
      end
    end

    Contract String => Maybe[String]
    def transaction_result(hex_hash)
      row = database[:txhistory].where(txid:hex_hash).first
      return if row.blank?
      row[:txresult]
    end

    Contract None => String
    def hostname
      host || DEFAULT_HOST
    end

    Contract None => Num
    def close_timeout
      150.0
    end

    Contract None => Num
    def sync_timeout
      if has_special_peers? and @catchup_complete
        # catchup-complete can take quite a while on testnet or pubnet; for now,
        # give such tests 36 hours. May require a change in strategy later.
        3600.0 * 36
      elsif has_special_peers?
        # testnet and pubnet have relatively more complex history
        # we give ourself:
        # 3 checkpoints + 20 minutes to apply buckets  + 0.5 second per ledger replayed
        (5.0 * 64 * 3) + ( 20 * 60 ) + (@catchup_recent ? (0.5 * @catchup_recent): 0)
      else
        # Checkpoints are made every 64 ledgers = 320s on a normal network,
        # or every 8 ledgers = 8s on an accelerated-time network; we give you
        # 3 checkpoints to make it to a sync (~16min) before giving up. The
        # accelerated-time variant tends to need more tries due to S3 not
        # admitting writes instantaneously, so we do not use a tighter bound
        # for that case, just use the same 16min value, despite commonly
        # succeeding in 20s or less.
        320.0 * 3
      end
    end

    Contract None => Bool
    def stopped?
      !running?
    end

    Contract None => Bool
    def launched?
      !!@launched
    end

    Contract None => Bool
    def crashed?
      launched? && stopped?
    end

    Contract Num => Bool
    def port_open?(port)
      begin
        Timeout::timeout(1) do
          begin
            $stderr.puts "#{idname} waiting for #{hostname}: #{port}"
            s = TCPSocket.new(hostname, port)
            s.close
            $stderr.puts "#{idname} ready on #{hostname}: #{port}"
            return true
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
            return false
          end
        end
      rescue Timeout::Error
      end
    
      return false
    end

    Contract None => Bool
    def http_port_open?
      port_open? http_port
    end

    Contract None => Bool
    def peer_port_open?
      port_open? peer_port
    end

    Contract None => Any
    def prepare
      # noop by default, implement in subclass to customize behavior
      nil
    end

    Contract None => Any
    def run
      raise Process::AlreadyRunning, "already running!" if running?
      raise Process::Crash, "process #{name} has crashed. cannot run process again" if crashed?

      setup
      launch_process
      @launched = true

      wait_for_http
      set_upgrades @protocol_version
    end

    Contract None => Any
    def setup
      if not @is_setup
        setup!
        @is_setup = true
      end
    end

    # Dumps the database of the process to the working directory, returning the path to the file written to
    Contract None => String
    def dump_database
      raise NotImplementedError, "implement in subclass"
    end

    private
    Contract None => Any
    def launch_process
      raise NotImplementedError, "implement in subclass"
    end

    Contract None => Any
    def setup!
      raise NotImplementedError, "implement in subclass"
    end

    Contract None => Any
    def wait_for_http
      wait_for_port http_port

      @wait_timeout.times do
        return if info! rescue sleep 1.0
      end

      raise "failed to get a successful info response after #{@wait_timeout} attempts"
    end

    Contract Num => Any
    def wait_for_port (port)
      @wait_timeout.times do
        return if port_open?(port)
        sleep 1.0
      end

      raise "port #{port} remained closed after #{@wait_timeout} attempts"
    end
  end
end
