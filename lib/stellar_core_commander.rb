require "stellar_core_commander/version"
require "active_support/all"
require "stellar-base"
require "contracts"

module StellarCoreCommander
  extend ActiveSupport::Autoload

  autoload :Commander
  autoload :Process
  autoload :WorkingDir
end
