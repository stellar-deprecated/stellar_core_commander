# StellarCoreCommander

A helper gem for scripting a [stellar-core](https://github.com/stellar/stellar-core).  This gem provides a system of creating isolated test networks into which you can play
transactions and record results.

The motivation for this project comes from the testing needs of [horizon](https://github.com/stellar/horizon).  Horizon uses `scc` to record the various testing scenarios that its suite uses.


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'stellar_core_commander'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install stellar_core_commander

## Assumptions about environment

At present `scc` makes a few assumptions about the environment it runs in that you should be aware.  In the event that your own environment differs from the below assumptions, `scc` will definitely break.

1.  Postgresql is installed locally and `pg_dump`, `createdb` and `dropdb` are available on your PATH
2.  The `which` command is available on your system.
3.  Postgresql is running and the current user has passwordless access to it.  Running `psql postgres -c "\l"` should confirm you're setup correctly.
4.  Your current user has access to create and drop postgres databases.  Test using: `createdb foobar && dropdb foobar`
5.  A working `stellar-core` binary is available on your path (or specified using the `--stellar-core-bin` flag)
6.  Your system has libsodium installed


## Usage As Command Line Tool

Installing `stellar_core_commander` installs the command line tool `scc`. `scc`
takes a recipe file, spins up a test network, plays the defined transactions against it, then dumps the ledger database to stdout.  `scc`'s usage is like so:

```bash
$ scc -r my_recipe.rb > out.sql
```

The above command will play the recipe written in `my_recipe.rb`, verify that all transactions within the recipe have succeeded, then dump the ledger database to `out.sql`

## Usage as a Library

TODO

## Writing Recipes

The heart of `scc` is a recipe, which is just a ruby script that executes in a context
that makes it easy to play transactions against the isolated test network.  Lets look at a simple recipe:

```ruby
account :scott
payment :master, :scott, [:native, 1000_000000]
```

Let's look at each statement in turn. `account :scott` declares a new unfunded account and binds it to the name `:scott`, which we will use in the next statement.  

The next statement is more complex: `payment :master, :scott, [:native, 1000_000000]`.  This statement encodes "Send 1000 lumens from the :master account to the :scott account".

`:master` (sometimes also called the "root" account) is a special account that is created when a new ledger is initialized.  We often use it in our recipes to fund other accounts, since in a ledgers initial state the :master account has all 100 billion lumen.

### Recipe Reference

All recipe execute within the context of a `StellarCoreCommander::Transactor`.  [See the code for all available methods](lib/stellar_core_commander/transactor.rb).

## Example Recipes

See [examples](examples).

## Contributing

1. Fork it ( https://github.com/[my-github-username]/stellar_core_commander/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
