module Ai
  class ChatService
    attr_reader :conversation_history, :data_context

    def initialize
      @conversation_history = []
      @data_context = {}
    end

    def add_exchange(user_query, ai_response, query_results = nil)
      exchange = {
        user_query: user_query,
        ai_response: ai_response,
        timestamp: Time.current
      }

      # Extract data context from results for future reference
      if query_results && query_results[:success]
        update_data_context(query_results)
      end

      @conversation_history << exchange

      # Keep only last 3 exchanges to manage context window
      @conversation_history = @conversation_history.last(3)
    end

    def build_context_for_prompt(app_type)
      return "" if @data_context.empty?

      context_parts = [ "=== CURRENT DATA CONTEXT ===", "App Type: #{app_type}" ]

      if @data_context[:developers]&.any?
        context_parts << "Recent Developers: #{@data_context[:developers].join(', ')}"
      end

      if @data_context[:repositories]&.any?
        context_parts << "Recent Repositories: #{@data_context[:repositories].join(', ')}"
      end

      if @data_context[:tickets]&.any?
        context_parts << "Recent Tickets: #{@data_context[:tickets].join(', ')}"
      end

      if @data_context[:pull_requests]&.any?
        context_parts << "Recent Pull Requests: #{@data_context[:pull_requests].join(', ')}"
      end

      context_parts << "When user says 'their', 'them', 'those', refer to the entities mentioned above."
      context_parts << "=== END CONTEXT ==="

      context_parts.join("\n")
    end

    def clear_context
      @conversation_history = []
      @data_context = {}
    end

    def has_context?
      @conversation_history.any? || @data_context.any?
    end

    def add_conversational_exchange(user_query, ai_response)
      exchange = {
        user_query: user_query,
        ai_response: ai_response,
        timestamp: Time.current,
        type: "conversational"
      }

      @conversation_history << exchange
      @conversation_history = @conversation_history.last(3)
    end

    private

    def update_data_context(query_results)
      return unless query_results[:raw_results]&.any?

      results = query_results[:raw_results]
      first_row = results.first

      # Extract developers
      if first_row.key?("name") || first_row.key?("developer_name")
        developer_names = results.map { |row| row["name"] || row["developer_name"] }.compact.uniq
        @data_context[:developers] = developer_names.first(5) if developer_names.any? # Limit to 5
      end

      # Extract repositories
      if first_row.key?("repository_name") || first_row.key?("full_name")
        repo_names = results.map { |row| row["repository_name"] || row["full_name"] }.compact.uniq
        @data_context[:repositories] = repo_names.first(5) if repo_names.any?
      end

      # Extract tickets
      if first_row.key?("key") || first_row.key?("title")
        ticket_info = results.map { |row| row["key"] || row["title"] }.compact.uniq
        @data_context[:tickets] = ticket_info.first(5) if ticket_info.any?
      end

      # Extract pull requests
      if first_row.key?("number") || first_row.key?("pr_title")
        pr_info = results.map { |row| "PR #{row['number']}" || row["pr_title"] }.compact.uniq
        @data_context[:pull_requests] = pr_info.first(5) if pr_info.any?
      end
    end

    def clean_developer_name(name)
      # Remove common suffixes that might indicate source system
      cleaned = name.to_s.gsub(/[-_](ap|jira|github)$/i, "")
      cleaned.strip
    end
  end
end
