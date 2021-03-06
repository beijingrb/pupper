module Pupper
  module Auditable
    extend ActiveSupport::Concern

    class_methods do
      def audit(*methods)
        underlying_methods = ''

        methods.each do |meth|
          underlying_methods << <<-RB.strip_heredoc
            def #{meth}
              audit { super }
              changes_applied
            end
          RB
        end

        prepend Module.new { module_eval(underlying_methods, __FILE__, __LINE__) }
      end

      def audit_action(*methods)
        underlying_methods = ''

        methods.each do |meth|
          underlying_methods << <<-RB.strip_heredoc
            def #{meth}
              begin
                super
              rescue Exception => e
                log_action('#{meth}', nil, e = e)
                throw e
              end
              log_action '#{meth}'
            end
          RB
        end

        prepend Module.new { module_eval(underlying_methods, __FILE__, __LINE__) }
      end
    end

    included do
      extend ActiveModel::Callbacks

      define_model_callbacks :update, :destroy, only: :around
      around_update :log_update
      around_destroy :log_destroy

      def audit(&block)
        run_callbacks :update, &block
        changes_applied
      end

      def audit_logs
        audit_model.where(auditable_type: model_name.name, auditable_id: primary_key).order(created_at: :desc)
      end

      def log_update(&block)
        log = ->(e = nil) { create_audit_log 'update', e }
        _log_action(log, &block)
      end

      def log_destroy(&block)
        log = ->(e = nil) { log_action('delete', nil, e) }
        _log_action(log, &block)
      end

      def create_audit_log(action, e = nil)
        return unless changed?

        log_action(action, changes, e)
      end

      def log_action(action, changes = nil, e = nil)
        audit_model.create(
          action: action,
          auditable_type: model_name.name,
          auditable_id: primary_key,
          user: Pupper.config.current_user,
          metadata: changes,
          success: e.nil?,
          exception: e
        )
      end

      def update_attributes(attrs)
        resp = {}
        run_callbacks(:update) do
          assign_attributes(attrs)
          resp = backend.update
        end

        changes_applied
        resp
      end

      def destroy
        run_callbacks(:destroy) do
          backend.destroy
        end
      end

      private

      def audit_model
        @audit_model ||= Pupper.config.audit_with.to_s.classify.constantize
      end

      def _log_action(log, &block)
        begin
          yield block
        rescue Exception => e
          log.call e
          throw e
        end
        log.call
      end
    end
  end
end
