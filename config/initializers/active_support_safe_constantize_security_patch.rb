# frozen_string_literal: true

require 'active_support/inflector'

# Backport of the Rails fix for GHSA-8474-xrp6-wh69
# (https://github.com/rails/rails/commit/210ac22d446c8e2625b091e79256806b836eee20).
# Action Cable passes the client-supplied channel name to safe_constantize before
# resolving a channel. Keep the existing anonymous and authenticated connection
# flows; fix the vulnerable LoadError matching at the shared Active Support entry point.
# Remove this backport after upgrading to Rails 8.0.5.2+ or 8.1.4.1+.
module ActiveSupport
  module Inflector
    module SafeConstantizeLiteralLoadErrorMatch
      def safe_constantize(camel_cased_word)
        constantize(camel_cased_word)
      rescue NameError => e
        raise if e.name && !(camel_cased_word.to_s.split('::').include?(e.name.to_s) ||
          e.name.to_s == camel_cased_word.to_s)
      rescue LoadError => e
        message = e.respond_to?(:original_message) ? e.original_message : e.message
        constant_name = camel_cased_word.split('::').find { |part| !part.empty? } || camel_cased_word
        raise unless message.include?("Unable to autoload constant #{constant_name}")
      end
    end

    singleton_class.prepend(SafeConstantizeLiteralLoadErrorMatch)
  end
end
