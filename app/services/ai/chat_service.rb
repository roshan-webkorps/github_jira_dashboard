# app/services/ai/chat_service.rb
module Ai
  class ChatService
    attr_reader :conversation_history, :data_context

    def initialize
      @conversation_history = []
      @data_context = {}
    end

    # Add data query exchange
    def add_exchange(user_query:, sql_query:, sql_results:, ai_response:)
      exchange = {
        user_query: user_query,
        sql_query: sql_query,
        ai_response: ai_response,
        timestamp: Time.current,
        type: "data_query"
      }

      # Update context from results
      update_data_context(sql_results) if sql_results.any?

      @conversation_history << exchange
      @conversation_history = @conversation_history.last(5)  # Keep last 5 exchanges
    end

    # Add conversational exchange (no SQL)
    def add_conversational_exchange(user_query, ai_response)
      exchange = {
        user_query: user_query,
        ai_response: ai_response,
        timestamp: Time.current,
        type: "conversational"
      }

      @conversation_history << exchange
      @conversation_history = @conversation_history.last(5)
    end

    # Build context for AI prompts
    def build_context_for_prompt(app_type)
      return "" if @data_context.empty? && @conversation_history.empty?

      context_parts = ["=== CONVERSATION CONTEXT ==="]
      context_parts << "App Type: #{app_type}"
      context_parts << ""

      # Add recent conversation summary
      if @conversation_history.any?
        context_parts << "Recent conversation:"
        @conversation_history.last(3).each do |exchange|
          context_parts << "User: #{exchange[:user_query]}"
          context_parts << "Assistant: #{exchange[:ai_response][0..150]}..."
          context_parts << ""
        end
      end

      # Add data context
      if @data_context[:developers]&.any?
        context_parts << "Developers in focus: #{@data_context[:developers].join(', ')}"
      end

      if @data_context[:repositories]&.any?
        context_parts << "Repositories in focus: #{@data_context[:repositories].join(', ')}"
      end

      if @data_context[:tickets]&.any?
        context_parts << "Recent tickets: #{@data_context[:tickets].join(', ')}"
      end

      if @data_context[:pull_requests]&.any?
        context_parts << "Recent pull requests: #{@data_context[:pull_requests].join(', ')}"
      end

      context_parts << ""
      context_parts << "When the user uses pronouns (he/she/they/their), they likely refer to the entities above."
      context_parts << "=== END CONTEXT ==="

      context_parts.join("\n")
    end

    # Clear all context
    def clear_context
      @conversation_history = []
      @data_context = {}
    end

    # Check if context exists
    def has_context?
      @conversation_history.any? || @data_context.any?
    end

    # Serialize to session
    def to_session_data
      {
        conversation_history: @conversation_history,
        data_context: @data_context
      }
    end

    # Restore from session
    def restore_from_session(session_data)
      return unless session_data.is_a?(Hash)
      
      @conversation_history = session_data[:conversation_history] || []
      @data_context = session_data[:data_context] || {}
      
      Rails.logger.info "Restored chat service: #{@conversation_history.length} exchanges, #{@data_context.keys.length} context keys"
    end

    private

    # Update data context from SQL results
    def update_data_context(sql_results)
      return unless sql_results.is_a?(Array) && sql_results.any?

      first_row = sql_results.first
      return unless first_row.is_a?(Hash)

      # Extract developers
      if first_row.key?("name") || first_row.key?("developer_name") || first_row.key?("developer")
        developer_names = sql_results.map { |row| 
          row["name"] || row["developer_name"] || row["developer"] 
        }.compact.uniq
        @data_context[:developers] = developer_names.first(5) if developer_names.any?
      end

      # Extract repositories
      if first_row.key?("repository_name") || first_row.key?("full_name")
        repo_names = sql_results.map { |row| 
          row["repository_name"] || row["full_name"] 
        }.compact.uniq
        @data_context[:repositories] = repo_names.first(5) if repo_names.any?
      end

      # Extract tickets
      if first_row.key?("key") || first_row.key?("title")
        ticket_info = sql_results.map { |row| 
          row["key"] || row["title"] 
        }.compact.uniq
        @data_context[:tickets] = ticket_info.first(5) if ticket_info.any?
      end

      # Extract pull requests
      if first_row.key?("number") || first_row.key?("pr_title")
        pr_info = sql_results.map { |row| 
          "PR ##{row['number']}" if row['number']
        }.compact.uniq
        @data_context[:pull_requests] = pr_info.first(5) if pr_info.any?
      end
    end
  end
end
