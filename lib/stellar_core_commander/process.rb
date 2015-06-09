module StellarCoreCommander

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
      host:           Or[String, nil],
      atlas:          Or[String, nil],
      atlas_interval: Num
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
      @host           = params[:host]
      @atlas          = params[:atlas]
      @atlas_interval = params[:atlas_interval]

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
    def peers
      @quorum.map do |q|
        p = @transactor.get_process(q)
        "#{p.hostname}:#{p.peer_port}"
      end
    end

    Contract None => Num
    def required_ports
      2
    end

    Contract None => Any
    def rm_working_dir
      FileUtils.rm_rf working_dir
    end

    Contract None => String
    def idname
      "#{@name}-#{@base_port}-#{@identity.address[0..5]}"
    end

    Contract None => Any
    def wait_for_ready
      loop do

        response = server.get("/info") rescue false

        if response
          body = ActiveSupport::JSON.decode(response.body)

          state = body["info"]["state"]
          $stderr.puts "state: #{state}"
          break if state == "Synced!"
        end

        $stderr.puts "waiting until stellar-core #{idname} is synced"
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

    Contract None => Hash
    def metrics
      response = server.get("/metrics")
      body = ActiveSupport::JSON.decode(response.body)
      body["metrics"]
    rescue
      {}
    end

    Contract None => Num
    def scp_ballots_prepared
      metrics["scp.ballot.prepare"]["count"]
    rescue
      0
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

    Contract Stellar::KeyPair => Num
    def sequence_for(account)
      row = database[:accounts].where(:accountid => account.address).first
      row[:seqnum]
    end

    Contract None => Num
    def latest_ledger
      database[:ledgerheaders].max(:ledgerseq)
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
          out: "stellar-core.log",
          err: "stellar-core.log",
        }]

      Dir.chdir working_dir do
        system(cmd, *args)
      end
    end

  end
end
