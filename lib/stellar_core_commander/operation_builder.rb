require 'bigdecimal'
module StellarCoreCommander

  class OperationBuilder
    include Contracts

    Asset = Or[
      [String, Symbol],
      :native,
    ]
    Amount = Or[
      [String, Symbol, Or[Num,String]],
      [:native, Or[Num,String]],
    ]

    OfferCurrencies = Or[
      {sell:Asset, for: Asset},
      {buy:Asset, with: Asset},
    ]

    Byte = And[Num, lambda{|n| (0..255).include? n}]
    ThresholdByte = Byte
    MasterWeightByte = Byte

    Thresholds = {
      low:    Maybe[ThresholdByte],
      medium: Maybe[ThresholdByte],
      high:   Maybe[ThresholdByte],
    }

    SetOptionsArgs = {
      inflation_dest: Maybe[Symbol],
      clear_flags:    Maybe[ArrayOf[Symbol]],
      set_flags:      Maybe[ArrayOf[Symbol]],
      thresholds:     Maybe[Thresholds],
      master_weight:  Maybe[MasterWeightByte],
      home_domain:    Maybe[String],
      signer:         Maybe[Stellar::Signer],
    }

    StellarBaseAsset = Or[[Symbol, String, Stellar::KeyPair], [:native]]

    MAX_LIMIT= BigDecimal.new((2**63)-1) / Stellar::ONE

    Contract Or[Transactor,HorizonCommander] => Any
    def initialize(transactor)
      @transactor = transactor
    end

    Memo = Or[
      Integer,
      String,
      [:id, Integer],
      [:text, String],
      [:hash, String],
      [:return, String],
    ]

    CommonOptions = {memo: Maybe[Memo]}
    PaymentOptions = Or[
      CommonOptions,
      CommonOptions.merge({path: ArrayOf[Asset], with:Amount}),
    ]

    Contract Symbol, Symbol, Amount, PaymentOptions => Any
    def payment(from, to, amount, options={})
      from = get_account from
      to   = get_account to

      attrs = {
        account:     from,
        destination: to,
        memo:        options[:memo],
        sequence:    next_sequence(from),
        amount:      normalize_amount(amount),
      }

      tx =  if options[:with]
              attrs[:with] = normalize_amount(options[:with])
              attrs[:path] = options[:path].map{|p| make_asset p}
              Stellar::Transaction.path_payment(attrs)
            else
              Stellar::Transaction.payment(attrs)
            end

      tx.to_envelope(from)
    end

    Contract Symbol, Symbol, Or[String,Num] => Any
    def create_account(account, funder=:master, starting_balance=1000)
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
      change_trust account, issuer, code, MAX_LIMIT
    end

    Contract Symbol, Symbol, String, Num => Any
    def change_trust(account, issuer, code, limit)
      account = get_account account

      Stellar::Transaction.change_trust({
        account:  account,
        sequence: next_sequence(account),
        line:     make_asset([code, issuer]),
        limit:    limit
      }).to_envelope(account)
    end

    Contract Symbol, Symbol, String, Bool => Any
    def allow_trust(account, trustor, code, authorize=true)
      asset = make_asset([code, account])
      account = get_account account
      trustor = get_account trustor


      Stellar::Transaction.allow_trust({
        account:  account,
        sequence: next_sequence(account),
        asset: asset,
        trustor:  trustor,
        authorize: authorize,
      }).to_envelope(account)
    end

    Contract Symbol, Symbol, String => Any
    def revoke_trust(account, trustor, code)
      allow_trust(account, trustor, code, false)
    end

    Contract Symbol, OfferCurrencies, Or[String,Num], Or[String,Num] => Any
    def offer(account, currencies, amount, price)
      account = get_account account

      buying, selling, price, amount = extract_offer(currencies, price, amount)

      Stellar::Transaction.manage_offer({
        account:  account,
        sequence: next_sequence(account),
        selling: selling,
        buying: buying,
        amount: amount,
        price: price,
      }).to_envelope(account)
    end

    Contract Symbol, OfferCurrencies, Or[String,Num], Or[String,Num] => Any
    def passive_offer(account, currencies, amount, price)
      account = get_account account

      buying, selling, price, amount = extract_offer(currencies, price, amount)

      Stellar::Transaction.create_passive_offer({
        account:  account,
        sequence: next_sequence(account),
        selling: selling,
        buying: buying,
        amount: amount,
        price: price,
      }).to_envelope(account)
    end

    Contract Symbol, SetOptionsArgs => Any
    def set_options(account, args)
      account = get_account account

      params = {
        account:  account,
        sequence: next_sequence(account),
      }

      if args[:inflation_dest].present?
        params[:inflation_dest] = get_account args[:inflation_dest]
      end

      if args[:set_flags].present?
        params[:set] = make_account_flags(args[:set_flags])
      end

      if args[:clear_flags].present?
        params[:clear] = make_account_flags(args[:clear_flags])
      end

      if args[:master_weight].present?
        params[:master_weight] = args[:master_weight]
      end

      if args[:thresholds].present?
        params[:low_threshold] = args[:thresholds][:low]
        params[:med_threshold] = args[:thresholds][:medium]
        params[:high_threshold] = args[:thresholds][:high]
      end

      if args[:home_domain].present?
        params[:home_domain] = args[:home_domain]
      end

      if args[:signer].present?
        params[:signer] = args[:signer]
      end

      tx = Stellar::Transaction.set_options(params)
      tx.to_envelope(account)
    end


    Contract Symbol, ArrayOf[Symbol] => Any
    def set_flags(account, flags)
      set_options account, set_flags: flags
    end

    Contract Symbol, ArrayOf[Symbol] => Any
    def clear_flags(account, flags)
      set_options account, clear_flags: flags
    end

    Contract Symbol => Any
    def require_trust_auth(account)
      set_flags account, [:auth_required_flag]
    end

    Contract Symbol, Stellar::KeyPair, Num => Any
    def add_signer(account, key, weight)
      sk = Stellar::SignerKey.new :signer_key_type_ed25519, key.raw_public_key

      set_options account, signer: Stellar::Signer.new({
        key:    sk,
        weight: weight
      })
    end

    Contract Symbol, Stellar::KeyPair => Any
    def remove_signer(account, key)
      add_signer account, key, 0
    end

    Contract(Symbol, MasterWeightByte => Any)
    def set_master_signer_weight(account, weight)
      set_options account, master_weight: weight
    end

    Contract(Symbol, Thresholds => Any)
    def set_thresholds(account, thresholds)
      set_options account, thresholds: thresholds
    end

    Contract(Symbol, Symbol => Any)
    def set_inflation_dest(account, destination)
      set_options account, inflation_dest: destination
    end

    Contract(Symbol, String => Any)
    def set_home_domain(account, domain)
      set_options account, home_domain: domain
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


    Contract None => Any
    def inflation(account=:master)
      account = get_account account

      tx = Stellar::Transaction.inflation({
        account:     account,
        sequence:    next_sequence(account),
      })

      tx.to_envelope(account)
    end


    Contract Symbol, String, String => Any
    def set_data(account, name, value)
      account = get_account account

      tx = Stellar::Transaction.manage_data({
        account:  account,
        sequence: next_sequence(account),
        name:     name,
        value:    value,
      })

      tx.to_envelope(account)
    end


    Contract Symbol, String => Any
    def clear_data(account, name)
      account = get_account account

      tx = Stellar::Transaction.manage_data({
        account:  account,
        sequence: next_sequence(account),
        name:     name,
      })

      tx.to_envelope(account)
    end

    private

    delegate :get_account, to: :@transactor
    delegate :next_sequence, to: :@transactor

    Contract Asset => StellarBaseAsset
    def make_asset(input)
      if input == :native
        return [:native]
      end

      code, issuer = *input
      issuer = get_account issuer

      [:alphanum4, code, issuer]
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

      amount = [:alphanum4] + amount
      amount[2] = get_account(amount[2]) # translate issuer to account

      amount
    end

    Contract OfferCurrencies, Or[String,Num], Or[String,Num] => [StellarBaseAsset, StellarBaseAsset, Or[String,Num], Or[String,Num]]
    def extract_offer(currencies, price, amount)
      if currencies.has_key?(:sell)
        buying = make_asset currencies[:for]
        selling = make_asset currencies[:sell]
      else
        buying = make_asset currencies[:buy]
        selling = make_asset currencies[:with]
        price, amount = invert_offer_price_and_amount(price, amount)
      end

      [buying, selling, price, amount]
    end

    Contract Or[String,Num], Or[String,Num] => [String, String]
    def invert_offer_price_and_amount(price, amount)
      price = BigDecimal.new(price, 7)
      price = (1 / price)

      amount = BigDecimal.new(amount, 7)
      amount = (amount / price).floor

      [price.to_s("F"), amount.to_s]
    end
  end
end
