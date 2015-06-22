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

    Contract({
      transactor:     Transactor,
      working_dir:    String,
      name:           Symbol,
      base_port:      Num,
      identity:       Stellar::KeyPair,
      quorum:         ArrayOf[Symbol],
      threshold:      Num,
      manual_close:   Or[Bool, nil],
      await_sync:     Or[Bool, nil],
      accelerate_time: Or[Bool, nil],
      forcescp:       Or[Bool, nil],
      host:           Or[String, nil],
      atlas:          Or[String, nil],
      atlas_interval: Num,
      use_s3:         Bool,
      s3_history_prefix: String,
      s3_history_region: String
    } => Any)
    def initialize(params)
      #config
      @transactor     = params[:transactor]
      @working_dir    = params[:working_dir]
      @name           = params[:name]
      @base_port      = params[:base_port]
      @identity       = params[:identity]
      @quorum         = params[:quorum]
      @threshold      = params[:threshold]
      @manual_close   = params[:manual_close] || false
      @await_sync     = params[:await_sync].nil? && true
      @accelerate_time = params[:accelerate_time] || false
      @forcescp       = params[:forcescp].nil? && true
      @host           = params[:host]
      @atlas          = params[:atlas]
      @atlas_interval = params[:atlas_interval]
      @use_s3         = params[:use_s3]
      @s3_history_region = params[:s3_history_region]
      @s3_history_prefix = params[:s3_history_prefix]

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

    Contract None => ArrayOf[String]
    def quorum
      @quorum.map do |q|
        @transactor.get_process(q).identity.address
      end
    end

    Contract None => ArrayOf[String]
    def peer_names
      @quorum.map {|x| x.to_s}
    end

    Contract None => ArrayOf[String]
    def peer_connections
      @quorum.map do |q|
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

    Contract None => Any
    def wait_for_ready
      loop do
        break if synced?
        $stderr.puts "waiting until stellar-core #{idname} is synced (state: #{info_field 'state'}, quorum heard: #{scp_quorum_heard})"
        sleep 1
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

    Contract None => Num
    def scp_ballots_prepared
      metrics_count "scp.ballot.prepare"
    end

    Contract None => Num
    def scp_quorum_heard
      metrics_count "scp.quorum.heard"
    end

    Contract Num, Num, Num => Any
    def start_load_generation(accounts, txs, txrate)
      server.get("/generateload?accounts=#{accounts}&txs=#{txs}&txrate=#{txrate}")
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
      database.select(:state).from(:storestate).filter(:statename=>name).first[:state]
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

    Contract None => Num
    def tx_count
      database.fetch("SELECT count(*) FROM txhistory").first[:count]
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
      database.fetch("SELECT * FROM trustlines ORDER BY accountid LIMIT 10").all
    end

    Contract None => ArrayOf[Any]
    def ten_txs
      database.fetch("SELECT * FROM txhistory ORDER BY txid LIMIT 10").all
    end

    Contract String, Any, Any => nil
    def check_equal(kind, x, y)
      raise UnexpectedDifference.new(kind, x, y) if x != y
    end

    Contract Process => nil
    def check_equal_state(other)
      check_equal "ledger", latest_ledger, other.latest_ledger
      check_equal "ledger hash", latest_ledger_hash, other.latest_ledger_hash
      check_equal "history", history_archive_state, other.history_archive_state

      check_equal "account count", account_count, other.account_count
      check_equal "trustline count", trustline_count, other.trustline_count
      check_equal "offer count", offer_count, other.offer_count
      check_equal "tx count", tx_count, other.tx_count

      check_equal "ten accounts", ten_accounts, other.ten_accounts
      check_equal "ten trustlines", ten_trustlines, other.ten_trustlines
      check_equal "ten offers", ten_offers, other.ten_offers
      check_equal "ten txs", ten_txs, other.ten_txs
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
      15.0
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

  end
end
