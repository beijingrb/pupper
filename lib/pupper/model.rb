require 'pupper/api_associations'
require 'pupper/auditable'
require 'pupper/trackable_attributes'

module Pupper
  module Model
    extend ActiveSupport::Concern

    class NoSuchBackend < NameError; end

    included do
      include ActiveModel::Model
      include ActiveModel::Serializers::JSON

      include Pupper::Auditable
      include Pupper::TrackableAttributes
      include Pupper::ApiAssociations

      delegate :backend, to: :class

      def initialize(**args)
        assocs, attrs = args.partition do |attr, value|
          attr.to_s =~ /_u?id$/ || value.is_a?(Hash)
        end.map(&Hash.method(:[]))

        assocs = build_associations(assocs)

        super(**attrs, **assocs)

        changes_applied

        backend.register_model(self)
      end

      def primary_key
        send(self.class.primary_key)
      end
    end

    class_methods do
      attr_writer :primary_key, :backend

      def primary_key
        @primary_key ||= :uid
      end

      def backend
        @backend ||= "#{model_name.name.pluralize}Client".constantize.new
      rescue NameError
        raise NoSuchBackend, <<-ERR
          Model #{model_name.name} is looking for an API client that doesn't exist!

          Either a) implement the new client:

            # app/api_clients/#{model_name.name.sub('::', '/').downcase.pluralize}_client.rb
            class #{model_name.name.pluralize}Client < Pupper::Backend
            end

          Or b) use a different client instead

            self.backend = Other::BackendClient

        ERR
      end
    end

    def to_json(*)
      attributes.except(*excluded_attrs).to_json
    end
  end
end