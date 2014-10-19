module JSONAPI::Consumer
  module ConnectionConcern
    extend ActiveSupport::Concern

    module ClassMethods
      def parse(response)
        if response.status && response.status == 204
          true
        else
          data = response.body
          result_data = data.fetch(json_key, [])
          d = result_data.map do |attrs|
            attrs = attrs.dup
            if attrs.has_key?(:links)
              attrs.merge!(attrs.delete(:links))
            end
            new(attrs)
          end
        end
      end

      # :nodoc:
      def _run_request(query_object)
        parse(_connection.send(query_object.request_method, query_object.path, query_object.params, query_object.headers))
      end

      # :nodoc:
      def _connection
        @connection ||= begin
          Faraday.new(url: self.host, ssl: self.ssl) do |conn|
            conn.request :json

            # conn.response :logger
            conn.use Middleware::RequestTimeout
            conn.use Middleware::ParseJson

            conn.use Middleware::RaiseError
            conn.adapter Faraday.default_adapter
          end
        end
      end
    end

    def is_valid?
      errors.empty?
    end

    def save
      query = persisted? ?
        Query::Update.new(self.class, self.serializable_hash) :
        Query::Create.new(self.class, self.serializable_hash)

      results = run_request(query)

      if self.errors.empty?
        self.attributes = results.first.attributes
        true
      else
        false
      end
    end

    def destroy
      if run_request(Query::Delete.new(self.class, self.serializable_hash))
        self.attributes.clear
        true
      else
        false
      end
    end

  private

    # :nodoc:
    def run_request(*args)
      begin
        self.errors.clear
        request = self.class._run_request(*args)
      rescue JSONAPI::Consumer::Errors::BadRequest => e
        e.errors.map do |error|
          process_error(error.dup)
        end
      end
    end

    # :nodoc:
    def process_error(err)
      field = err.fetch('path', '')
      attr = field.match(/\A\/\/(\w+)\z/)[1]
      if attr && has_attribute?(attr)
        self.errors.add(attr.to_sym, err.fetch('detail', ''))
      else
        self.errors.add(:base, err.fetch('detail', ''))
      end
    end
  end
end