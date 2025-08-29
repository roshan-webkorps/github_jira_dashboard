module Ai
  class SummaryGenerator
    def initialize(bedrock_client)
      @bedrock_client = bedrock_client
    end

    def generate_business_summary(user_query, results, description, app_type)
      return nil if results.empty?

      begin
        app_display_name = app_type == "pioneer" ? "Pioneer" : "Legacy"

        # Create data insights for context
        data_insights = analyze_results_for_insights(results)

        summary_prompt = build_summary_prompt(
          user_query,
          description,
          results,
          data_insights,
          app_display_name
        )

        response = call_bedrock_api(summary_prompt, app_type)
        parsed = parse_response(response)
        parsed["summary"]
      rescue => e
        Rails.logger.error "Business summary generation error: #{e.message}"
        generate_fallback_summary(results, description)
      end
    end

    private

    def build_summary_prompt(user_query, description, results, data_insights, app_display_name)
      <<~PROMPT
        You are analyzing #{app_display_name} team performance data for: "#{user_query}"

        Query: #{description}
        Results: #{results.length} records found

        Key Data Insights: #{data_insights}

        Sample data (first 2 records):
        #{format_sample_data(results)}

        Create a business-friendly summary that:
        1. **Explains what the data shows** in simple terms (avoid technical jargon)
        2. **Highlights 2-3 key findings** that matter to team management
        3. **Suggests 1-2 actionable improvements** based on the data
        4. **Keeps it concise** (maximum 3 sentences)
        5. **Uses plain English** - write as if explaining to a non-technical manager

        Example tone: "John leads the team with 340 commits this week. Sarah and Mike have lighter workloads, suggesting they could take on more challenging tasks. Consider redistributing work to prevent John from burning out."

        Respond with JSON only: {"summary": "your business summary"}
      PROMPT
    end

    def format_sample_data(results)
      results.first(2).map do |row|
        row.map { |k, v| "#{k}: #{v}" }.join(", ")
      end.join("\n")
    end

    def analyze_results_for_insights(results)
      return "No data" if results.empty?

      insights = []

      # Find numeric columns for analysis
      numeric_columns = results.first.select { |k, v| v.is_a?(Numeric) }

      numeric_columns.each do |column, _|
        values = results.map { |row| row[column].to_f }
        if values.length > 1
          avg = (values.sum / values.length).round(1)
          insights << "#{column.humanize}: average #{avg}, range #{values.min}-#{values.max}"
        else
          insights << "#{column.humanize}: #{values.first}"
        end
      end

      # Analyze distribution if we have names/categories
      if results.first.key?("name")
        total_records = results.length
        insights << "#{total_records} #{total_records == 1 ? 'person' : 'people'} analyzed"
      end

      insights.join("; ")
    end

    def generate_fallback_summary(results, description)
      count = results.length
      entity = case description.downcase
      when /developer/ then count == 1 ? "developer" : "developers"
      when /repository|repo/ then count == 1 ? "repository" : "repositories"
      when /ticket/ then count == 1 ? "ticket" : "tickets"
      when /commit/ then count == 1 ? "commit" : "commits"
      when /pull request|pr/ then count == 1 ? "pull request" : "pull requests"
      else "result#{'s' unless count == 1}"
      end

      "Found #{count} #{entity}. #{description}"
    end

    def call_bedrock_api(prompt, app_type)
      request_body = {
        anthropic_version: "bedrock-2023-05-31",
        max_tokens: 300, # Shorter for concise summaries
        temperature: 0.1,
        system: "You generate concise, business-friendly summaries for team analytics data. Always respond with valid JSON only.",
        messages: [ { role: "user", content: prompt } ]
      }

      response = @bedrock_client.invoke_model({
        model_id: "us.anthropic.claude-3-5-sonnet-20241022-v2:0",
        body: request_body.to_json,
        content_type: "application/json"
      })

      response_body = JSON.parse(response.body.read)
      response_body.dig("content", 0, "text")&.strip
    end

    def parse_response(response)
      return {} if response.nil? || response.strip.empty?

      # Clean response
      cleaned = response.strip
      cleaned = cleaned[1...-1] if cleaned.start_with?('"') && cleaned.end_with?('"')
      cleaned = cleaned.gsub('\\n', "\n").gsub('\\"', '"').gsub("\\\\", "\\")

      JSON.parse(cleaned)
    rescue JSON::ParserError => e
      Rails.logger.error "Summary JSON parsing failed: #{e.message}"

      # Extract summary with regex as fallback
      summary_match = response.match(/"summary":\s*"((?:[^"\\]|\\.)*)"/m)
      if summary_match
        { "summary" => summary_match[1].gsub('\\"', '"').gsub("\\\\", "\\") }
      else
        { "summary" => "Analysis complete. Review the data above for insights." }
      end
    end
  end
end
