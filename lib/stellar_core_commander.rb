require "stellar_core_commander/version"
require "active_support/all"
require "stellar-base"
require "contracts"
require "faraday"
require "faraday_middleware"
require "fileutils"
require "sequel"
require "pg"
require "uri"

module StellarCoreCommander
  extend ActiveSupport::Autoload

  autoload :Commander

  autoload :Cmd
  autoload :CmdResult
  autoload :Process
  autoload :LocalProcess
  autoload :Container
  autoload :DockerProcess

  autoload :Transactor
  autoload :TransactionBuilder
  autoload :TransactionMultiBuilder

  autoload :Convert

  autoload :HorizonCommander
  autoload :SequenceTracker

  module Concerns
    extend ActiveSupport::Autoload

    autoload :NamedObjects
    autoload :TracksAccounts
  end
end
