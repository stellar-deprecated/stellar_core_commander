module StellarCoreCommander

  class OperationBuilder
    include Contracts

    Currency = Or[
      [String, Symbol],
      :native,
    ]
    Amount = Or[
      [String, Symbol, Num],
      [:native, Num],
    ]

    OfferCurrencies = Or[
      {sell:Currency, for: Currency},
      {buy:Currency, with: Currency},
    ]

    ThresholdByte = And[Num, lambda{|n| (0..255).include? n}]

    Thresholds = {
      low:           ThresholdByte,
      medium:        ThresholdByte,
      high:          ThresholdByte,
      master_weight: ThresholdByte
    }

    Contract Transactor => Any
    def initialize(transactor)
      @transactor = transactor
    end

    Contract Symbol, Symbol, Amount, Or[{}, {path: ArrayOf[Currency], with:Amount}] => Any
    def payment(from, to, amount, options={})
      from = get_account from
      to   = get_account to

      attrs = {
        account:     from,
        destination: to,
        sequence:    next_sequence(from),
        amount:      normalize_amount(amount),
      }

      tx =  if options[:with]
              attrs[:with] = normalize_amount(options[:with])
              attrs[:path] = options[:path].map{|p| make_currency p}
              Stellar::Transaction.path_payment(attrs)
            else
              Stellar::Transaction.payment(attrs)
            end

      tx.to_envelope(from)
    end

    Contract Symbol, Symbol, Num => Any
    def create_account(account, funder=:master, starting_balance=1000_0000000)
      account = get_account account
      funder  = get_account funder

      Stellar::Transaction.create_account({
        account:          funder,
        destination:      account,
        sequence:         next_sequence(funder),
        starting_balance: starting_balance,
      }).to_envelope(funder)
    end

    Contract Symbol, Symbol, String => Any
    def trust(account, issuer, code)
      change_trust account, issuer, code, (2**63)-1
    end

    Contract Symbol, Symbol, String, Num => Any
    def change_trust(account, issuer, code, limit)
      account = get_account account

      Stellar::Transaction.change_trust({
        account:  account,
        sequence: next_sequence(account),
        line:     make_currency([code, issuer]),
        limit:    limit
      }).to_envelope(account)
    end

    Contract Symbol, Symbol, String, Bool => Any
    def allow_trust(account, trustor, code, authorize=true)
      currency = make_currency([code, account])
      account = get_account account
      trustor = get_account trustor


      Stellar::Transaction.allow_trust({
        account:  account,
        sequence: next_sequence(account),
        currency: currency,
        trustor:  trustor,
        authorize: authorize,
      }).to_envelope(account)
    end

    Contract Symbol, Symbol, String => Any
    def revoke_trust(account, trustor, code)
      allow_trust(account, trustor, code, false)
    end

    Contract Symbol, OfferCurrencies, Num, Num => Any
    def offer(account, currencies, amount, price)
      account = get_account account

      if currencies.has_key?(:sell)
        taker_pays = make_currency currencies[:for]
        taker_gets = make_currency currencies[:sell]
      else
        taker_pays = make_currency currencies[:buy]
        taker_gets = make_currency currencies[:with]
        price = 1 / price
        amount = (amount * price).floor
      end

      Stellar::Transaction.create_offer({
        account:  account,
        sequence: next_sequence(account),
        taker_gets: taker_gets,
        taker_pays: taker_pays,
        amount: amount,
        price: price,
      }).to_envelope(account)
    end


    Contract Symbol => Any
    def require_trust_auth(account)
      set_flags account, [:auth_required_flag]
    end

    Contract Symbol, ArrayOf[Symbol] => Any
    def set_flags(account, flags)
      account = get_account account

      tx = Stellar::Transaction.set_options({
        account:  account,
        sequence: next_sequence(account),
        set:      make_account_flags(flags),
      })

      tx.to_envelope(account)
    end


    Contract Symbol, Stellar::KeyPair, Num => Any
    def add_signer(account, key, weight)
      account = get_account account

      tx = Stellar::Transaction.set_options({
        account:  account,
        sequence: next_sequence(account),
        signer:   Stellar::Signer.new({
          pub_key: key.public_key,
          weight: weight
        }),
      })

      tx.to_envelope(account)
    end

    Contract(Symbol, Thresholds => Any)
    def set_thresholds(account, thresholds)
      account = get_account account

      tx = Stellar::Transaction.set_options({
        account:    account,
        sequence:   next_sequence(account),
        thresholds: make_thresholds_word(thresholds),
      })

      tx.to_envelope(account)
    end

    Contract Symbol, Symbol => Any
    def merge_account(account, into)
      account = get_account account
      into    = get_account into

      tx = Stellar::Transaction.account_merge({
        account:     account,
        sequence:    next_sequence(account),
        destination: into,
      })

      tx.to_envelope(account)
    end

    private

    delegate :get_account, to: :@transactor
    delegate :next_sequence, to: :@transactor

    Contract Currency => Or[[Symbol, String, Stellar::KeyPair], [:native]]
    def make_currency(input)
      if input == :native
        return [:native]
      end

      code, issuer = *input
      issuer = get_account issuer

      [:alphanum, code, issuer]
    end

    def make_account_flags(flags=nil)
      flags ||= []
      flags.map{|f| Stellar::AccountFlags.send(f)}
    end

    Contract Thresholds => String
    def make_thresholds_word(thresholds)
      thresholds.values_at(:master_weight, :low, :medium, :high).pack("C*")
    end

    Contract Amount => Any
    def normalize_amount(amount)
      return amount if amount.first == :native

      amount = [:alphanum] + amount
      amount[2] = get_account(amount[2]) # translate issuer to account

      amount
    end

  end
end
