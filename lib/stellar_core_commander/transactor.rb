require 'fileutils'
module StellarCoreCommander


  #
  # A transactor plays transactions against a stellar-core test node.
  #
  #
  class Transactor
    include Contracts
    include Concerns::NamedObjects
    include Concerns::TracksAccounts

    class FailedTransaction < StandardError ; end
    class MissingTransaction < StandardError ; end

    attr_reader :manual_close

    Contract Commander => Any
    def initialize(commander)
      @commander         = commander
      @transaction_builder = TransactionBuilder.new(self)
      @manual_close      = false

      account :master, Stellar::KeyPair.master
    end

    def require_process_running
      if @process.nil?
        @process = @commander.get_root_process self

        if get_named(@process.name).blank?
          add_named @process.name, @process
        end
      end
      
      @commander.start_all_processes
      @commander.require_processes_in_sync
    end

    def shutdown(*args)
      @process.shutdown *args
    end

    Contract String => Any
    #
    # Runs the provided recipe against the process identified by @process
    #
    # @param recipe_path [String] path to the recipe file
    #
    def run_recipe(recipe_path)
      recipe_content = IO.read(recipe_path)
      instance_eval recipe_content, recipe_path, 1
    rescue => e
      crash_recipe e
    end


    # Contract Nil => Any
    # #
    # # Runs the provided recipe against the process identified by @process
    # #
    # # @param recipe_path [String] path to the recipe file
    # #
    # def transaction(&block)
    #   tx = TransactionBuilder.new(self)
    #   tx.run_recipe block

    #   envelope = tx.build
    #   submit_transaction envelope
    # end

    Contract Symbol => Any
    # recipe_step is a helper method to define
    # a method that follows the common procedure of executing a recipe step:
    #
    # 1. ensure all processes are running
    # 2. build the envelope by forwarding to the operation builder
    # 3. submit the envelope to the process
    #
    # @param name [Symbol] the method to be defined and delegated to @transaction_builder
    def self.recipe_step(name)
      define_method name do |*args, &block|
        require_process_running
        envelope = @transaction_builder.send(name, *args)

        if block.present?
          block.call envelope
        end

        submit_transaction envelope
      end
    end


    #
    # @see StellarCoreCommander::TransactionBuilder#payment
    def payment(*args, &block)
      require_process_running
      envelope = @transaction_builder.payment(*args)

      if block.present?
        block.call envelope
      end

      submit_transaction envelope do |result|
        payment_result = result.result.results!.first.tr!.value
        raise FailedTransaction unless payment_result.code.value >= 0
      end
    end

    # @see StellarCoreCommander::TransactionBuilder#create_account
    recipe_step :create_account

    # @see StellarCoreCommander::TransactionBuilder#trust
    recipe_step :trust

    # @see StellarCoreCommander::TransactionBuilder#change_trust
    recipe_step :change_trust

    # @see StellarCoreCommander::TransactionBuilder#offer
    recipe_step :offer

    # @see StellarCoreCommander::TransactionBuilder#passive_offer
    recipe_step :passive_offer

    # @see StellarCoreCommander::TransactionBuilder#set_options
    recipe_step :set_options

    # @see StellarCoreCommander::TransactionBuilder#set_flags
    recipe_step :set_flags

    # @see StellarCoreCommander::TransactionBuilder#clear_flags
    recipe_step :clear_flags

    # @see StellarCoreCommander::TransactionBuilder#require_trust_auth
    recipe_step :require_trust_auth

    # @see StellarCoreCommander::TransactionBuilder#add_signer
    recipe_step :add_signer

    # @see StellarCoreCommander::TransactionBuilder#remove_signer
    recipe_step :remove_signer

    # @see StellarCoreCommander::TransactionBuilder#add_onetime_signer
    recipe_step :add_onetime_signer

    # @see StellarCoreCommander::TransactionBuilder#set_master_signer_weight
    recipe_step :set_master_signer_weight


    # @see StellarCoreCommander::TransactionBuilder#set_thresholds
    recipe_step :set_thresholds

    # @see StellarCoreCommander::TransactionBuilder#set_inflation_dest
    recipe_step :set_inflation_dest

    # @see StellarCoreCommander::TransactionBuilder#set_home_domain
    recipe_step :set_home_domain

    # @see StellarCoreCommander::TransactionBuilder#allow_trust
    recipe_step :allow_trust

    # @see StellarCoreCommander::TransactionBuilder#revoke_trust
    recipe_step :revoke_trust

    # @see StellarCoreCommander::TransactionBuilder#merge_account
    recipe_step :merge_account

    # @see StellarCoreCommander::TransactionBuilder#inflation
    recipe_step :inflation

    # @see StellarCoreCommander::TransactionBuilder#set_data
    recipe_step :set_data

    # @see StellarCoreCommander::TransactionBuilder#clear_data
    recipe_step :clear_data

    # @see StellarCoreCommander::OperationBuilder#bump_sequence
    recipe_step :bump_sequence

    Contract None => Any
    #
    # Triggers a ledger close.  Any unvalidated transaction will
    # be validated, which will trigger an error if any fail to be validated
    #
    def close_ledger
      require_process_running
      nretries = 3
      loop do
        residual = []
        @process.close_ledger
        @process.unverified.each do |eb|
          begin
            envelope, after_confirmation = *eb
            result = validate_transaction envelope
            after_confirmation.call(result) if after_confirmation
          rescue MissingTransaction
            $stderr.puts "Failed to validate tx: #{Convert.to_hex envelope.tx.hash}"
            $stderr.puts "could not be found in txhistory table on process #{@process.name}"
            residual << eb
          rescue FailedTransaction
            if not @commander.process_options[:allow_failed_transactions]
              $stderr.puts "Failed to validate tx: #{Convert.to_hex envelope.tx.hash}"
              $stderr.puts "failed result: #{result.to_xdr(:base64)}"
              residual << eb
            end
          end
        end
        if residual.empty?
          @process.unverified.clear
          break
        end
        if nretries == 0
          raise "Missing or failed txs after multiple close attempts"
        else
          $stderr.puts "retrying close"
          nretries -= 1
          @process.unverified = residual
          residual = []
        end
      end
    end

    Contract None => Num
    def ledger_num
      require_process_running
      @process.ledger_num
    end

    Contract Num, Symbol => Any
    def catchup(ledger, mode=:minimal)
      require_process_running
      @process.catchup ledger, mode
    end

    Contract None => Any
    def crash
      @process.crash
    end

    Contract None => Any
    def cleanup_all
      @commander.cleanup
      @process = nil
    end

    Contract Symbol => Process
    def get_process(name)
      @named[name].tap do |found|
        unless found.is_a?(Process)
          raise ArgumentError, "#{name.inspect} is not process"
        end
      end
    end

    Contract Symbol, Num, Num, Or[Symbol, Num], Num => Any
    def start_load_generation(mode=:create, accounts=10000000, txs=10000000, txrate=500, batchsize=100)
      $stderr.puts "starting load generation: #{mode} mode, #{accounts} accounts, #{txs} txs, #{txrate} tx/s, #{batchsize} batchsize"
      @process.start_load_generation mode, accounts, txs, txrate, batchsize
    end

    Contract None => Bool
    def load_generation_complete
      @process.load_generation_complete
    end

    Contract Symbol, Num, Num, Or[Symbol, Num], Num => Any
    def generate_load_and_await_completion(mode, accounts, txs, txrate, batchsize)
      runs = @process.load_generation_runs
      start_load_generation mode, accounts, txs, txrate, batchsize
      num_retries = if mode == :create then accounts else txs end

      retry_until_true retries: num_retries do
        txs = @process.transactions_applied
        r = @process.load_generation_runs
        tps = @process.transactions_per_second
        ops = @process.operations_per_second
        $stderr.puts "loadgen runs: #{r}, ledger: #{ledger_num}, accounts: #{accounts}, txs: #{txs}, actual tx/s: #{tps} op/s: #{ops}"
        r != runs
      end
    end

    Contract None => Hash
    def metrics
      @process.metrics
    end

    Contract None => Any
    def clear_metrics
      @process.clear_metrics
    end

    Contract None => Num
    def protocol_version
      @process.get_protocol_version
    end

    Contract String, Symbol, Num, Num, Or[Symbol, Num], Num => Any
    def record_performance_metrics(fname, txtype, accounts, txs, txrate, batchsize)
      @commander.record_performance_metrics fname, txtype, accounts, txs, txrate, batchsize
    end

    Contract Symbol, ArrayOf[Symbol], Hash => Process
    def process(name, quorum=[name], options={})

      if @manual_close and quorum.size != 1
        raise "Cannot use `process` with multi-node quorum, this recipe has previously declared  `use_manual_close`."
      end

      $stderr.puts "creating process #{name}"
      p = @commander.make_process self, name, quorum, options
      $stderr.puts "process #{name} is #{p.idname}"
      add_named name, p
    end

    Contract Symbol, Proc => Any
    def on(process_name)
      require_process_running
      tmp = @process
      p = get_process process_name
      $stderr.puts "executing steps on #{p.idname}"
      @process = p
      yield
    ensure
      @process = tmp
    end

    def retry_until_true(**opts, &block)
      retries = opts[:retries] || 20
      timeout = opts[:timeout] || 3
      while retries > 0
        b = begin yield block end
        if b
          return b
        end
        retries -= 1
        $stderr.puts "sleeping #{timeout} secs, #{retries} retries left"
        sleep timeout
      end
      raise "Ran out of retries while waiting for success"
    end

    Contract Stellar::KeyPair => Num
    def next_sequence(account)
      require_process_running
      base_sequence  = @process.sequence_for(account)
      inflight_count = @process.unverified.select{|e| e.first.tx.source_account == account.public_key}.length

      base_sequence + inflight_count + 1
    end

    Contract Or[Symbol, Stellar::KeyPair] => Bool
    def account_created(account)
      require_process_running
      if account.is_a?(Symbol)
        account = get_account(account)
      end
      begin
        @process.account_row(account)
        return true
      rescue
        return false
      end
    end

    Contract Or[Symbol, Stellar::KeyPair] => Num
    def balance(account)
      require_process_running
      if account.is_a?(Symbol)
        account = get_account(account)
      end
      raise "no process!" unless @process
      @process.balance_for(account)
    end

    Contract None => Any
    def use_manual_close()
      $stderr.puts "using manual_close mode"
      @manual_close = true
    end

    Contract None => Bool
    def check_no_error_metrics
      @commander.check_no_process_error_metrics
    end

    Contract Or[Num, String] => Any
    def set_upgrades(protocolversion)
      @process.set_upgrades protocolversion
    end

    Contract None => Any
    def check_uses_latest_protocol_version
      latest_protocol_version = @process.get_protocol_version
      current_protocol_version = @process.get_current_protocol_version
      if latest_protocol_version != current_protocol_version
        raise "protocol version not upgraded to #{latest_protocol_version}, still at #{current_protocol_version} with #{@process.ledger_num}"
      end
    end

    Contract ArrayOf[Or[Symbol, Process]] => Bool
    def check_equal_ledger_objects(processes)
      raise "no process!" unless @process
      for p in processes
        if p.is_a?(Symbol)
          p = get_process(p)
        end
        @process.check_equal_ledger_objects(p)
      end
      true
    end

    Contract Or[Symbol, Process] => Any
    def check_ledger_sequence_matches(other)
      raise "no process!" unless @process
      if other.is_a?(Symbol)
        other = get_process(other)
      end
      @process.check_ledger_sequence_matches(other)
    end

    Contract Or[Symbol, Process] => Any
    def check_integrity_against(other)
      check_no_error_metrics
      check_equal_ledger_objects [other]
      check_ledger_sequence_matches other
    end

    private

    Contract Stellar::TransactionEnvelope, Or[nil, Proc] => Any
    def submit_transaction(envelope, &after_confirmation)
      require_process_running
      b64    = envelope.to_xdr(:base64)

      # submit to process
      @process.submit_transaction b64

      # register envelope for validation after ledger is closed
      @process.unverified << [envelope, after_confirmation]
    end

    Contract Stellar::TransactionEnvelope => Stellar::TransactionResult
    def validate_transaction(envelope)
      raw_hash = envelope.tx.hash
      hex_hash = Convert.to_hex(raw_hash)
      base64_envelope = Convert.to_base64(Stellar::TransactionEnvelope.to_xdr(envelope))

      base64_result = @process.transaction_result(hex_hash)

      raise MissingTransaction if base64_result.blank?

      raw_result = Convert.from_base64(base64_result)

      pair = Stellar::TransactionResultPair.from_xdr(raw_result)
      result = pair.result

      if not @commander.process_options[:allow_failed_transactions]
        # ensure success for every operation
        expected = Stellar::TransactionResultCode.tx_success
        actual = result.result.code
        raise "tx: #{hex_hash} #{base64_envelope} transaction failed: #{base64_result}" unless expected == actual
      end

      result
    end

    Contract Exception => Any
    def crash_recipe(e)
      puts
      puts "Error! (#{e.class.name}): #{e.message}"
      puts
      puts e.backtrace.
        reject{|l| l =~ %r{gems/contracts-.+?/} }. # filter contract frames
        join("\n")
      puts

      exit 1
    end

  end
end
