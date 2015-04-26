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
      from = get_account from
      to   = get_account to

      if amount.first != :native
        amount    = [:iso4217] + amount
        amount[2] = get_account(amount[2])
        amount[1] = amount[1].ljust(4, "\x00")
      end

      envelope = Stellar::Transaction.payment({
        account:     from,
        destination: to,
        sequence:    next_sequence(from),
        amount:      amount,
      }).to_envelope(from)

      submit_transaction envelope
    end

    Contract Symbol, Symbol, String => Any
    def trust(account, issuer, code)
      change_trust account, issuer, code, (2**63)-1
    end    

    Contract Symbol, Symbol, String, Num => Any
    def change_trust(account, issuer, code, limit)
      account = get_account account
      issuer  = get_account issuer
      code    = code.ljust(4, "\x00")

      tx = Stellar::Transaction.change_trust({
        account:  account,
        sequence: next_sequence(account),
        line:     [:iso4217, code, issuer],
        limit:    limit
      })

      envelope = tx.to_envelope(account)

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
      @unverified.clear
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

    Contract Symbol => Stellar::KeyPair
    def get_account(name)
      @named[name].tap do |found|
        unless found.is_a?(Stellar::KeyPair)
          raise ArgumentError, "#{name.inspect} is not account"
        end
      end
    end

    Contract Stellar::KeyPair => Num
    def next_sequence(account)
      base_sequence  = @process.sequence_for(account)
      inflight_count = @unverified.select{|e| e.tx.source_account == account.public_key}.length
      
      base_sequence + inflight_count + 1
    end

  end
end