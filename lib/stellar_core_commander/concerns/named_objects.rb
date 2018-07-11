
module StellarCoreCommander
  module Concerns
    module NamedObjects
      include Contracts

      private
      Contract Symbol, Any => Any
      def add_named(name, object)
        @named ||= {}.with_indifferent_access
        if @named.has_key?(name)
          raise ArgumentError, "#{name} is already registered"
        end
        @named[name] = object
        object
      end

      Contract Symbol => Any
      def get_named(name)
        @named ||= {}.with_indifferent_access
        @named[name]
      end
    end
  end
end
