# app/services/ai/chat_service.rb
module Ai
  class ChatService
    attr_reader :conversation_history, :data_context, :developer_analyses

    def initialize
      @conversation_history = []
      @data_context = {}
      @developer_analyses = {}  # Store pre-computed analysis by developer name
    end

    # Store comprehensive developer analysis
    def store_developer_analysis(developer_name, analysis_data)
      return unless developer_name.present?
      
      @developer_analyses[normalize_name(developer_name)] = {
        performance_summary: analysis_data[:performance_summary],
        strengths: analysis_data[:strengths],
        improvements: analysis_data[:improvements],
        metrics: analysis_data[:metrics],
        generated_at: Time.current
      }
      
      Rails.logger.info "Stored analysis for #{developer_name}"
    end

    # Retrieve stored developer analysis
    def get_developer_analysis(developer_name, analysis_type = nil)
      return nil unless developer_name.present?
      
      analysis = @developer_analyses[normalize_name(developer_name)]
      return nil unless analysis
      
      case analysis_type
      when :improvements
        analysis[:improvements]
      when :strengths
        analysis[:strengths]
      when :summary
        analysis[:performance_summary]
      when :metrics
        analysis[:metrics]
      else
        analysis  # Return full analysis
      end
    end

    # Check if we have analysis for a developer
    def has_analysis_for?(developer_name)
      return false unless developer_name.present?
      @developer_analyses.key?(normalize_name(developer_name))
    end

    def add_exchange(user_query, ai_response, query_results = nil)
      exchange = {
        user_query: user_query,
        ai_response: ai_response,
        timestamp: Time.current
      }

      if query_results && query_results[:success]
        update_data_context(query_results)
      end

      @conversation_history << exchange
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
      @developer_analyses = {}
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

    # Serialize to session
    def to_session_data
      {
        conversation_history: @conversation_history,
        data_context: @data_context,
        developer_analyses: @developer_analyses
      }
    end

    # Restore from session
    def restore_from_session(session_data)
      return unless session_data.is_a?(Hash)
      
      @conversation_history = session_data[:conversation_history] || []
      @data_context = session_data[:data_context] || {}
      @developer_analyses = session_data[:developer_analyses] || {}
      
      Rails.logger.info "Restored chat service: #{@developer_analyses.keys.length} analyses, #{@conversation_history.length} exchanges"
    end

    private

    def normalize_name(name)
      name.to_s.downcase.strip
    end

    def update_data_context(query_results)
      return unless query_results[:raw_results]&.any?

      results = query_results[:raw_results]
      first_row = results.first

      # Extract developers (including 'developer' key from SQL results)
      if first_row.key?("name") || first_row.key?("developer_name") || first_row.key?("developer")
        developer_names = results.map { |row| 
          row["name"] || row["developer_name"] || row["developer"] 
        }.compact.uniq
        @data_context[:developers] = developer_names.first(5) if developer_names.any?
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
  end
end
