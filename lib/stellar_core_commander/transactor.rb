require 'fileutils'
module StellarCoreCommander


  # 
  # A transactor plays transactions against a stellar-core test node.
  # 
  # 
  class Transactor
    include Contracts

    Amount = Any #TODO

    Contract Process => Any
    def initialize(process)
      @process    = process
      @named      = {}.with_indifferent_access
      @unverified = []
      account :master, Stellar::KeyPair.from_raw_seed("allmylifemyhearthasbeensearching")
    end

    Contract String => Any

    # 
    # Runs the provided recipe against the process identified by @process
    # 
    # @param recipe_path [String] path to the recipe file
    # 
    def run_recipe(recipe_path)
      raise "stellar-core not running" unless @process.running? 

      recipe_content = IO.read(recipe_path)
      instance_eval recipe_content
    end


    Contract Symbol, Stellar::KeyPair => Any
    # 
    # Registered an account for this scenario.  Future calls may refer to
    # the name provided.
    # 
    # @param name [Symbol] the name to register the keypair at
    # @param keypair=Stellar::KeyPair.random [Stellar::KeyPair] the keypair to use for this account
    # 
    def account(name, keypair=Stellar::KeyPair.random)
      unless keypair.is_a?(Stellar::KeyPair)
        raise ArgumentError, "`#{keypair.class.name}` is not `Stellar::KeyPair`"
      end

      add_named name, keypair
    end

    Contract Symbol, Symbol, Amount => Any
    def payment(from, to, amount)

      from, to = @named.values_at(from, to)

      unless from.is_a?(Stellar::KeyPair)
        raise ArgumentError, "#{from.inspect} is not account"
      end

      unless to.is_a?(Stellar::KeyPair)
        raise ArgumentError, "#{to.inspect} is not account"
      end

      base_sequence  = @process.sequence_for(from)
      inflight_count = @unverified.select{|e| e.tx.source_account == from.public_key}.length
      sequence       = base_sequence + inflight_count + 1

      envelope = Stellar::Transaction.payment({
        account:     from,
        destination: to,
        sequence:    sequence,
        amount:      amount,
      }).to_envelope(from)

      submit_transaction envelope
    end

    Contract None => Any
    # 
    # Triggers a ledger close.  Any unvalidated transaction will
    # be validated, which will trigger an error if any fail to be validated
    # 
    def close_ledger
      @process.close_ledger
      # TODO: validate in-flight transactions
    end

    private
    Contract Symbol, Any => Any
    def add_named(name, object)
      if @named.has_key?(name)
        raise ArgumentError, "#{name} is already registered"
      end

      @named[name] = object
    end

    Contract Stellar::TransactionEnvelope => Any
    def submit_transaction(envelope)
      hex    = envelope.to_xdr(:hex)
      @process.submit_transaction hex

      # submit to process
      @unverified << envelope
    end

  end
end