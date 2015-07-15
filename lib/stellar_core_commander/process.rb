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
    attr_reader :threshold
    attr_reader :host
    attr_reader :atlas
    attr_reader :atlas_interval

    DEFAULT_HOST = '127.0.0.1'

    SPECIAL_PEERS = {
      :testnet1 => {
        :dns => "core-testnet1.stellar.org",
        :key => "gTDZhQ14WuP8rQ9SrkS1EhWNhZyybv97cHNsGRADKQtBoJpTTk",
        :name => "core-testnet-001",
        :get => "curl -sf https://s3-eu-west-1.amazonaws.com/history.stellar.org/prd/core-testnet/%s/{0} -o {1}"
      },
      :testnet2 => {
        :dns => "core-testnet2.stellar.org",
        :key => "gsjjWTsQP5C2HpcetiLz4LDa9VECGvZMTyhPUDWi57ZKafV5sA4",
        :name => "core-testnet-002",
        :get => "curl -sf https://s3-eu-west-1.amazonaws.com/history.stellar.org/prd/core-testnet/%s/{0} -o {1}"
      },
      :testnet3 => {
        :dns => "core-testnet3.stellar.org",
        :key => "gSCB2HML88CvMwt2iryJGdS61gDr2nhMeYFVWF2B4m6w5js73T",
        :name => "core-testnet-003",
        :get => "curl -sf https://s3-eu-west-1.amazonaws.com/history.stellar.org/prd/core-testnet/%s/{0} -o {1}"
      }
    }

    Contract({
      transactor:        Transactor,
      working_dir:       String,
      name:              Symbol,
      base_port:         Num,
      identity:          Stellar::KeyPair,
      quorum:            ArrayOf[Symbol],
      threshold:         Num,
      manual_close:      Maybe[Bool],
      await_sync:        Maybe[Bool],
      accelerate_time:   Maybe[Bool],
      catchup_complete:  Maybe[Bool],
      forcescp:          Maybe[Bool],
      host:              Maybe[String],
      atlas:             Maybe[String],
      atlas_interval:    Num,
      use_s3:            Bool,
      s3_history_prefix: String,
      s3_history_region: String,
      database_url:      Maybe[String],
      keep_database:     Maybe[Bool],
    } => Any)
    def initialize(params)
      #config
      @transactor        = params[:transactor]
      @working_dir       = params[:working_dir]
      @name              = params[:name]
      @base_port         = params[:base_port]
      @identity          = params[:identity]
      @quorum            = params[:quorum]
      @threshold         = params[:threshold]
      @manual_close      = params[:manual_close] || false
      @await_sync        = params.fetch(:await_sync, true)
      @accelerate_time   = params[:accelerate_time] || false
      @catchup_complete  = params[:catchup_complete] || false
      @forcescp          = params.fetch(:forcescp, true)
      @host              = params[:host]
      @atlas             = params[:atlas]
      @atlas_interval    = params[:atlas_interval]
      @use_s3            = params[:use_s3]
      @s3_history_region = params[:s3_history_region]
      @s3_history_prefix = params[:s3_history_prefix]
      @database_url      = params[:database_url]
      @keep_database     = params[:keep_database]

      # state
      @unverified   = []

      if not @quorum.include? @name
        @quorum << @name
      end

      @server = Faraday.new(url: "http://#{hostname}:#{http_port}") do |conn|
        conn.request :url_encoded
        conn.adapter Faraday.default_adapter
      end
    end

    Contract None => ArrayOf[Symbol]
    def special_quorum_nodes
      @quorum.select {|q| SPECIAL_PEERS.has_key? q}
    end

    Contract None => Bool
    def has_special_nodes?
      @quorum.any? {|q| SPECIAL_PEERS.has_key? q}
    end

    Contract Symbol, Proc => ArrayOf[String]
    def quorum_map_or_special_field(field)
      specials = special_quorum_nodes
      if specials.empty?
        @quorum.map do |q|
          yield q
        end
      else
        specials.map {|q| SPECIAL_PEERS[q][field]}
      end
    end

    Contract None => ArrayOf[String]
    def quorum
      quorum_map_or_special_field :key do |q|
          @transactor.get_process(q).identity.address
      end
    end

    Contract None => ArrayOf[String]
    def peer_names
      quorum_map_or_special_field :name do |q|
        q.to_s
      end
    end

    Contract None => ArrayOf[String]
    def peer_connections
      quorum_map_or_special_field :dns do |q|
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

    Contract None => String
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
      base = "postgresql://dbname=#{database_name} host=#{database_host} port=#{database_port}"
      base << " user=#{database_user}" if database_user.present?
      base << " password=#{database_password}" if database_password.present?
      base << " host=#{database_host}" if database_host.present?

      base
    end

    Contract None => Any
    def wait_for_ready
      Timeout.timeout(sync_timeout) do
        loop do
          break if synced?
          $stderr.puts "waiting until stellar-core #{idname} is synced (state: #{info_field 'state'}, quorum heard: #{scp_quorum_heard})"
          sleep 1
        end
      end
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
          current_ledger = latest_ledger

          case
          when current_ledger == next_ledger
            break
          when current_ledger > next_ledger
            raise "#{idname} jumped two ledgers, from #{prev_ledger} to #{current_ledger}"
          else
            $stderr.puts "#{idname} waiting for ledger #{next_ledger} (current: #{current_ledger}, ballots prepared: #{scp_ballots_prepared})"
            sleep 0.5
          end
        end
      end
      $stderr.puts "#{idname} closed #{latest_ledger}"

      true
    end

    Contract Num, Symbol => Any
    def catchup(ledger, mode)
      server.get("/catchup?ledger=#{ledger}&mode=#{mode}")
    end

    Contract None => Hash
    def info
      response = server.get("/info")
      body = ActiveSupport::JSON.decode(response.body)
      body["info"]
    rescue
      {}
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

    Contract None => Num
    def ledger_num
      (info_field "ledger")["num"]
    rescue
      0
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

    Contract String => Num
    def metrics_count(k)
      m = metrics
      m[k]["count"]
    rescue
      0
    end

    Contract None => Any
    def dump_metrics
      response = server.get("/metrics")
      File.open("#{working_dir}/stellar-metrics.json", 'w') {|f| f.write(response.body) }
    rescue
      nil
    end

    Contract None => Num
    def scp_ballots_prepared
      metrics_count "scp.ballot.prepare"
    end

    Contract None => Num
    def scp_quorum_heard
      metrics_count "scp.quorum.heard"
    end

    Contract None => Bool
    def check_no_error_metrics
      m = metrics
      for metric in ["scp.ballot.invalid",
                     "scp.ballot.invalidsig",
                     "scp.envelope.invalidsig",
                     "scp.value.invalid",
                     "scp.sync.lost",
                     "history.publish.failure",
                     "history.catchup.failure"]
        c = m[metric]["count"] rescue 0
        if c != 0
          raise "nonzero metrics count for #{metric}: #{c}"
        end
      end
      true
    end

    Contract Num, Num, Num => Any
    def start_load_generation(accounts, txs, txrate)
      server.get("/generateload?accounts=#{accounts}&txs=#{txs}&txrate=#{txrate}")
    end

    Contract None => Num
    def load_generation_runs
      metrics_count "loadgen.run.complete"
    end

    Contract None => Num
    def transactions_applied
      metrics_count "ledger.transaction.apply"
    end

    Contract None => Any
    def start_checkdb
      server.get("/checkdb")
    end

    Contract None => Num
    def checkdb_runs
      metrics_count "bucket.checkdb.execute"
    end

    Contract None => Num
    def objects_checked
      metrics_count "bucket.checkdb.object-compare"
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
        raise "transaction on #{idname} failed: #{body.inspect}"
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
      (account_row account)[:seqnum]
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
      database.fetch("SELECT * FROM offers ORDER BY accountid LIMIT 10").all
    end

    Contract None => ArrayOf[Any]
    def ten_trustlines
      database.fetch("SELECT * FROM trustlines ORDER BY accountid, issuer, alphanumcurrency LIMIT 10").all
    end

    Contract String, Any, Any => nil
    def check_equal(kind, x, y)
      raise UnexpectedDifference.new(kind, x, y) if x != y
    end

    Contract Process => nil
    def check_equal_ledger_objects(other)
      check_equal "account count", account_count, other.account_count
      check_equal "trustline count", trustline_count, other.trustline_count
      check_equal "offer count", offer_count, other.offer_count

      check_equal "ten accounts", ten_accounts, other.ten_accounts
      check_equal "ten trustlines", ten_trustlines, other.ten_trustlines
      check_equal "ten offers", ten_offers, other.ten_offers
    end

    Contract Process => Any
    def check_ledger_sequence_is_prefix_of(other)
      q = "SELECT ledgerseq, ledgerhash FROM ledgerheaders ORDER BY ledgerseq"
      our_headers = other.database.fetch(q).all
      other_headers = other.database.fetch(q).all
      our_hash = {}
      other_hash = {}
      other_headers.each do |row|
        other_hash[row[:ledgerseq]] = row[:ledgerhash]
      end
      our_headers.each do |row|
        check_equal "ledger hashes", other_hash[row[:ledgerseq]], row[:ledgerhash]
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
      60.0 * 8
    end

    Contract String, ArrayOf[String] => Maybe[Bool]
    def run_cmd(cmd, args)
      args += [{
          out: ["stellar-core.log", "a"],
          err: ["stellar-core.log", "a"],
        }]

      Dir.chdir working_dir do
        system(cmd, *args)
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
    end

    private
    Contract None => Any
    def launch_process
      raise NotImplementedError, "implement in subclass"
    end

    Contract None => Any
    def setup
      raise NotImplementedError, "implement in subclass"
    end
  end
end
